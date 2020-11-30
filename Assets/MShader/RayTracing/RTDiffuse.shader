﻿Shader "Unlit/Diffuse"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
         _Color ("Main Color", Color) = (1, 1, 1, 1)
        _Fuzz ("Fuzz", float) = 1
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
            CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float4 _MainTex_ST;
            float _Fuzz;
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
			  //return (1/2*M_PI);
              return max(0.0f, cosine / M_PI);
            }

            [shader("closesthit")]
            void ClosestHitShader(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
            {
                IntersectionVertex vertexN;
                GetCurrentIntersectionVertex(attributeData,vertexN);
                float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
                float3 normalWS = normalize(mul(objectToWorld, vertexN.normalOS));
                float2 uv = vertexN.uv;

                float4 color = float4(0, 0, 0, 1);
                if (rayIntersection.remainingDepth > 0)
                {
                  // Get position in world space.
                  float3 origin = WorldRayOrigin();
                  float3 direction = WorldRayDirection();
                  float t = RayTCurrent();
                  float3 positionWS = origin + direction * t;

                  // Make reflection ray.
                  float3 reflectDir = reflect(direction, normalWS);
                  if (dot(reflectDir, normalWS) < 0.0f)
                    reflectDir = direction;

                  ONB uvw;
                  ONBBuildFromW(uvw, normalWS);
                  RayDesc rayDescriptor;
                  rayDescriptor.Origin = positionWS + 0.001f * reflectDir;
           
                  rayDescriptor.Direction =  reflectDir*(1-_Fuzz) + _Fuzz * ONBLocal(uvw, GetRandomCosineDirection(rayIntersection.PRNGStates));
                  rayDescriptor.TMin = 1e-5f;
                  rayDescriptor.TMax = _CameraFarDistance;

                  // Tracing reflection.
                  RayIntersection reflectionRayIntersection;
                  reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
                  reflectionRayIntersection.PRNGStates = rayIntersection.PRNGStates;
                  reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);

                 float pdf = dot(normalWS, rayDescriptor.Direction) / (2*M_PI);

                  TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 0, 1, 0, rayDescriptor, reflectionRayIntersection);

                  rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
                  //color = reflectionRayIntersection.color;
                  
                  color = ScatteringPDF(origin, direction, t, normalWS, rayDescriptor.Direction) * reflectionRayIntersection.color / pdf;
                  color = max(float4(0, 0, 0, 0), color);
                }
                float4 texColor = _Color * _MainTex.SampleLevel(sampler_MainTex, uv, 0);
                rayIntersection.color =texColor*0.5f * color;
            }

            ENDHLSL
        }
    }
}
