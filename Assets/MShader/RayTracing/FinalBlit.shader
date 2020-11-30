Shader "Unlit/FinalBlit"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
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
            sampler2D _TempSceneTex;
            sampler2D _TempRTSceneTex;
            sampler2D _DenoiseTemp;
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 TempSceneTex = tex2D(_TempSceneTex, i.uv);
                fixed4 TempRTSceneTex = tex2D(_TempRTSceneTex, i.uv);
                if(TempRTSceneTex.r==0&&TempRTSceneTex.g==0&&TempRTSceneTex.b==0&&TempRTSceneTex.a==0)
                    TempRTSceneTex=TempSceneTex;
                return TempRTSceneTex;
            }
            ENDHLSL
        }
    }
}
