#ifndef RTSKY_H_
#define RTSKY_H_

int _Procedural;
float3 _Tint;
float _Exposure;
float _Rotation;
Texture2D _Skybox; 
SamplerState sampler_Skybox;
half4 _MainTex_HDR;

float3 RotateAroundYInDegrees (float3 vertex, float degrees)
{
    float alpha = degrees * 3.14159265359f / 180.0f;
    float sina, cosa;
    sincos(alpha, sina, cosa);
    float2x2 m = float2x2(cosa, -sina, sina, cosa);
    return float3(mul(m, vertex.xz), vertex.y).xzy;
}

inline half3 DecodeHDR (half4 data, half4 decodeInstructions)
{
    half alpha = decodeInstructions.w * (data.a - 1.0) + 1.0;	
	return (decodeInstructions.x * pow(alpha, decodeInstructions.y)) * data.rgb;
}

inline float2 ToRadialCoords(float3 coords)
{
    float3 normalizedCoords = normalize(coords);
    float latitude = acos(normalizedCoords.y);
    float longitude = atan2(normalizedCoords.z, normalizedCoords.x);
    float2 sphereCoords = float2(longitude, latitude) * float2(0.5/3.14159265359f, 1.0/3.14159265359f);
    return float2(0.5,1.0) - sphereCoords;
}

void SkyLight(inout RayIntersection rayIntersection, const int distance = 50) {
	if(rayIntersection.remainingDepth < 0){
		return;
	}
	rayIntersection.remainingDepth = 0;
	if (_Procedural > 0.5) {
		rayIntersection.color = lerp(_MainTex_HDR, float4(_Tint,1), smoothstep(-0.1, 0.1, WorldRayDirection().y));
	}
	else {
		float2 tc = ToRadialCoords(RotateAroundYInDegrees(WorldRayDirection(), -_Rotation));

		half4 tex = _Skybox.SampleLevel(sampler_Skybox, tc, 0);
		half3 c = DecodeHDR(tex, _MainTex_HDR);
		c = c * _Tint.rgb * 2;
		c *= _Exposure;
		rayIntersection.color = float4(c,1);
	}
}

#endif