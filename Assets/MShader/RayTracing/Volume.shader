Shader "Unlit/RTVolume"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
         _Color ("Main Color", Color) = (1, 1, 1, 1)
         _Density ("Density", Float) = 0.01
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
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }
            half4 _Color;
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

           TEXTURE2D(_MainTex);
           SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float4 _MainTex_ST;
            float _Density;
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

            [shader("closesthit")]
            void ClosestHitShader(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
            {
                if (rayIntersection.remainingDepth < 0) // is inner ray.
                {
                  rayIntersection.hitT = RayTCurrent();
                  return;
                }
                
                float t1 = RayTCurrent();
                RayDesc rayDescriptor;
                rayDescriptor.Origin = WorldRayOrigin();
                rayDescriptor.Direction = WorldRayDirection();
                rayDescriptor.TMin = t1+ 1e-5f;
                rayDescriptor.TMax = _CameraFarDistance;

                RayIntersection innerRayIntersection;
                //Set it to calculate only the distance from the current point to the backface 
                innerRayIntersection.remainingDepth = min(-1, rayIntersection.remainingDepth - 1);
                innerRayIntersection.PRNGStates = rayIntersection.PRNGStates;
                innerRayIntersection.color = float4(0, 0, 0, 0);
                innerRayIntersection.hitT = 0.0f;
                //cull face
                TraceRay(_AccelerationStructure, RAY_FLAG_CULL_FRONT_FACING_TRIANGLES, 0xFF, 0, 1, 0, rayDescriptor, innerRayIntersection);
                float t2 = innerRayIntersection.hitT;
                //inner distance
                float distanceInsideBoundary = t2 - t1;
                float hitDistance = -(1.0f / _Density) * log(GetRandomValue(rayIntersection.PRNGStates));
      
                //Internal
                if (hitDistance < distanceInsideBoundary)
                {
                  const float t = t1 + hitDistance;
                  rayDescriptor.Origin = rayDescriptor.Origin + t * rayDescriptor.Direction;
                  rayDescriptor.Direction = GetRandomOnUnitSphere(rayIntersection.PRNGStates);
                  rayDescriptor.TMin = 1e-5f;
                  rayDescriptor.TMax = _CameraFarDistance;

                  RayIntersection scatteredRayIntersection;
                  scatteredRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
                  scatteredRayIntersection.PRNGStates = rayIntersection.PRNGStates;
                  scatteredRayIntersection.color = float4(0, 0, 0, 0);
                  TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 0, 1, 0, rayDescriptor, scatteredRayIntersection);
                  rayIntersection.PRNGStates = scatteredRayIntersection.PRNGStates;
                  rayIntersection.color = _Color * scatteredRayIntersection.color;
                }
                else//Shoot through
                {
                      const float t = t2 + 1e-5f;
                      rayDescriptor.Origin = rayDescriptor.Origin + t * rayDescriptor.Direction;
                      rayDescriptor.Direction = rayDescriptor.Direction;

                      rayDescriptor.TMin = 1e-5f;
                      rayDescriptor.TMax = _CameraFarDistance;

                      RayIntersection scatteredRayIntersection;
                      scatteredRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
                      scatteredRayIntersection.PRNGStates = rayIntersection.PRNGStates;
                      scatteredRayIntersection.color = float4(0, 0, 0, 0);
                      TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 0, 1, 0, rayDescriptor, scatteredRayIntersection);
                      rayIntersection.PRNGStates = scatteredRayIntersection.PRNGStates;
                      rayIntersection.color = scatteredRayIntersection.color;
                }
      }

            ENDHLSL
        }
    }
}
