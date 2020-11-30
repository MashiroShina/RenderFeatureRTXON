Shader "Hidden/QuickDenoise"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
	}
		SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 100

		CGINCLUDE
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			sampler2D _MainTex;
			int2 _Pixel_WH;
			float _DenoiseStrength;

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = o.vertex.xy;
				o.uv = o.uv / 2 + 0.5;
				o.uv.y = 1 - o.uv.y;
				return o;
			}

			float Luminance(float3 col) {
				return col.r* 0.299 + col.g * 0.587 + col.b * 0.114;
			}


			float4 smartDeNoise(float2 uv, float threshold = 0.1, float sigma = 2, float kSigma = 2)
			{
				#define INV_SQRT_OF_2PI 0.39894228040143267793994605993439  // 1.0/SQRT_OF_2PI
				#define INV_PI 0.31830988618379067153776752674503
				float radius = round(kSigma * sigma);
				float radQ = radius * radius;

				float invSigmaQx2 = .5 / (sigma * sigma);      // 1.0 / (sigma^2 * 2.0)
				float invSigmaQx2PI = INV_PI * invSigmaQx2;    // 1.0 / (sqrt(PI) * sigma)

				float invThresholdSqx2 = .5 / (threshold * threshold);     // 1.0 / (sigma^2 * 2.0)
				float invThresholdSqrt2PI = INV_SQRT_OF_2PI / threshold;   // 1.0 / (sqrt(2*PI) * sigma)

				float4 centrPx = tex2D(_MainTex, uv);

				int2 size = _Pixel_WH;

				float zBuff = 0;
				float4 aBuff = 0;

				for (float x = -radius; x <= radius; x++) {
					float pt = sqrt(radQ - x * x);  // pt = yRadius: have circular trend
					for (float y = -pt; y <= pt; y++) {
						float2 d = float2(x, y) / size;

						float blurFactor = exp(-dot(d, d) * invSigmaQx2) * invSigmaQx2;

						float4 walkPx = tex2D(_MainTex, uv + d);

						float4 dC = walkPx - centrPx;
						float deltaFactor = exp(-dot(dC, dC) * invThresholdSqx2) * invThresholdSqrt2PI * blurFactor;

						zBuff += deltaFactor;
						aBuff += deltaFactor * walkPx;
					}
				}
				return aBuff / zBuff;
			}
		ENDCG


		Pass
		{	
			Ztest off
			ZWrite off

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			fixed4 frag(v2f i) : SV_Target
			{
				return smartDeNoise(i.uv,_DenoiseStrength);
			}
			ENDCG
		}
	}
}
