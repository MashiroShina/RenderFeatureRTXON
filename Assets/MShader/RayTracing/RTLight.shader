Shader "Unlit/RTLight"
{
    Properties
    {
         _MainTex ("Texture", 2D) = "white" {}
         _Color ("Main Color", Color) = (1, 1, 1, 1)
         _Intensity ("Main Color", float) = 1
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
            float _Intensity;
            CBUFFER_END

            struct IntersectionVertex
            {
                // Object space normal of the vertex
                float3 normalOS;
                float2 uv;
            };

            void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
            {
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
                float2 uv= INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.uv, v1.uv, v2.uv, barycentricCoordinates);
                outVertex.uv = uv;
            }

            [shader("closesthit")]
            void ClosestHitShader(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
            {
                IntersectionVertex vertexN;
                GetCurrentIntersectionVertex(attributeData,vertexN);
                float2 uv = vertexN.uv;
                float4 texColor = _MainTex.SampleLevel(sampler_MainTex, uv, 0);
                rayIntersection.color = float4(texColor.rgb*_Intensity *_Color ,1.0f);
            }

            ENDHLSL
        }
    }
}
