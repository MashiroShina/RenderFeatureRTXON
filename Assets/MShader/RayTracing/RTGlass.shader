Shader "Unlit/GS"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
         _Color ("Main Color", Color) = (1, 1, 1, 1)
        _Fuzz ("Fuzz", float) = 1
        _IOR("IOR",Range(0,3))=1

        _BumpMap("Normal Map", 2D) = "bump" {}
		_BumpScale("BumpScale", Range(-10,10)) = 0.0
        _MipScale("MipScale", Range(0.1, 10)) = 10
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };
            sampler2D _MainTex;
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _Color;
            CBUFFER_END

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
				//o.vertex.y += sin(_Time.y * 10 + o.vertex.x + o.vertex.y);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col*_Color;
            }
            ENDCG
        }
    }
     SubShader
    {
        Pass
        {
            Name "RayTracing"
            Tags { "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #pragma raytracing test

            #include "./Common.hlsl"
            #include "./PRNG.hlsl"
            #include "./ONB.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float _Fuzz;
            float _IOR;

            float4 _MainTex_ST;
            float4 _BumpMap_ST;
            float _MipScale;
            float _BumpScale;
           
            CBUFFER_END

            struct IntersectionVertex
            {
                // Object space normal of the vertex
                float3 normalOS;
                float2 uv;
            };

            void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
            {
                outVertex.normalOS = UnityRayTracingFetchVertexAttribute3
                (vertexIndex, kVertexAttributeNormal);//normal
                outVertex.uv  = UnityRayTracingFetchVertexAttribute2
                (vertexIndex, kVertexAttributeTexCoord0);//uv
            }

            void GetCurrentIntersectionVertex(AttributeData attributeData, out IntersectionVertex outVertex)
            {
                // Fetch the indices of the currentr triangle
                uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

                // Fetch the 3 vertices
                IntersectionVertex v0, v1, v2;
                FetchIntersectionVertex(triangleIndices.x, v0);
                FetchIntersectionVertex(triangleIndices.y, v1);
                FetchIntersectionVertex(triangleIndices.z, v2);

                // Compute the full barycentric coordinates
                float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);
                float3 normalOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates);
                outVertex.normalOS = normalOS;
                float2 uv= INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.uv, v1.uv, v2.uv, barycentricCoordinates);
                outVertex.uv = uv;
            }

            float ScatteringPDF(float3 inOrigin, float3 inDirection, float inT, float3 hitNormal, float3 scatteredDir)
            {
              float cosine = dot(hitNormal, scatteredDir);
              return max(0.0f, cosine / M_PI);
            }
              half3 UnpackScaleNormalRGorAG(half4 packednormal, half bumpScale)
            {

	            // This do the trick
	            packednormal.x *= packednormal.w;

	            half3 normal;
	            normal.xy = (packednormal.xy * 2 - 1);

	            // SM2.0: instruction count limitation
	            // SM2.0: normal scaler is not supported
	            normal.xy *= bumpScale;

	            normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
	            return normal;
            }
            half3 UnpackScaleNormal(half4 packednormal, half bumpScale)
            {
	            return UnpackScaleNormalRGorAG(packednormal, bumpScale);
            }

            inline float schlick(float cosine, float IOR)
            {
              float r0 = (1.0f - IOR) / (1.0f + IOR);
              r0 = r0 * r0;
              return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
            }

            [shader("closesthit")]
            void ClosestHitShader(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
            {
                IntersectionVertex vertexN;
                GetCurrentIntersectionVertex(attributeData,vertexN);
                float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
                float3 normalWS = normalize(mul(objectToWorld, vertexN.normalOS));

                  float distance = RayTCurrent();
                float mip = max(log2(distance / _MipScale), 0);
                float2 uv = vertexN.uv.xy* _BumpMap_ST.xy + _BumpMap_ST.zw;
                
                half3 normal = UnpackScaleNormal(
                lerp(_BumpMap.SampleLevel(sampler_BumpMap, uv, floor(mip)), 
                _BumpMap.SampleLevel(sampler_BumpMap, uv, floor(mip) + 1), mip - floor(mip)), _BumpScale);
                if (_BumpScale!=0)
                    normalWS =normal;// lerp(normal,normalWS,_BumpScale);


                float4 color = float4(0, 0, 0, 1);
                if (rayIntersection.remainingDepth > 0)
                {
                  // Get position in world space.
                  float3 origin = WorldRayOrigin();
                  float3 direction = WorldRayDirection();
                  float t = RayTCurrent();
                  float3 positionWS = origin + direction * t;

                  ONB uvw;
                  ONBBuildFromW(uvw, normalWS);
                  normalWS += _Fuzz * ONBLocal(uvw, GetRandomCosineDirection(rayIntersection.PRNGStates));
                  normalWS = normalize(normalWS);
                  //float2 sample_2D;
				  //sample_2D.x = rayIntersection.PRNGStates;
				  //sample_2D.y = rayIntersection.PRNGStates;
                  //float4 n = ImportanceSampleGGX(sample_2D, 1 - _Fuzz);
                  
                  // Make reflection & refraction ray.
                  float3 outwardNormal;
                  float niOverNt;
                  float reflectProb;
                  float cosine;
                   //when ray shoot through object back into vacuum,
                  if (dot(-direction, normalWS) > 0.0f)
                   {
                     outwardNormal = normalWS;
                     niOverNt = 1.0f / _IOR;
                     cosine = _IOR * dot(-direction, normalWS);
                   }
                   else//ray in object
                   {
                     outwardNormal = -normalWS;
                     niOverNt = _IOR;
                     cosine = -dot(-direction, normalWS);
                   }
                  //critical Refl
                  reflectProb = schlick(cosine, _IOR);
                  float3 scatteredDir;
                  //Now we generate a random number between 0.0 and 1.0. If it’s smaller than reflective coefficient, the scattered ray is recorded as reflected; If it’s bigger than reflective coefficient, the scattered ray is recorded as refracted.
                  if (GetRandomValue(rayIntersection.PRNGStates) < reflectProb)
                    scatteredDir = reflect(direction, normalWS);
                  else
                    scatteredDir = refract(direction, outwardNormal, niOverNt);

                  // Make reflection ray.
                  RayDesc rayDescriptor;
                  rayDescriptor.Origin = positionWS + 1e-5f * scatteredDir;
                  rayDescriptor.Direction = scatteredDir;
                  
               
                  rayDescriptor.TMin = 1e-5f;
                  rayDescriptor.TMax = _CameraFarDistance;

                  // Tracing reflection.
                  RayIntersection reflectionRayIntersection;
                  reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
                  reflectionRayIntersection.PRNGStates = rayIntersection.PRNGStates;
                  reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);

                  float pdf = dot(normalWS, rayDescriptor.Direction) / M_PI;

                  TraceRay(_AccelerationStructure, RAY_FLAG_NONE, 0xFF, 0, 1, 0, rayDescriptor, reflectionRayIntersection);

                  rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
                  color = reflectionRayIntersection.color;
           
                }
                 float4 texColor = _Color * _MainTex.SampleLevel(sampler_MainTex, uv, 0);
                rayIntersection.color =texColor*_Color * color;

            }

            ENDHLSL
        }
    }
}
