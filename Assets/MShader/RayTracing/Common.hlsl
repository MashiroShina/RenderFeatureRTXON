#include "UnityRaytracingMeshUtils.cginc" 
//C:\Program Files\Unity\Hub\Editor\2019.3.2f1\Editor\Data\CGIncludes

#define CBUFFER_START(name) cbuffer name {
#define CBUFFER_END };

#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)
#define SAMPLE_TEXTURE2D_LOD(textureName, samplerName, coord2, lod) textureName.SampleLevel(samplerName, coord2, lod)
#define TEXTURE2D(textureName) Texture2D textureName
#define SAMPLER(samplerName) SamplerState samplerName

CBUFFER_START(CameraBuffer)
float4x4 _InvCameraViewProj;
float3 _WorldSpaceCameraPos;
float _CameraFarDistance;
float3 _FocusCameraLeftBottomCorner;
float3 _FocusCameraRight;
float3 _FocusCameraUp;
float2 _FocusCameraSize;
float _FocusCameraHalfAperture;
CBUFFER_END

RaytracingAccelerationStructure _AccelerationStructure;

struct RayIntersection
{
  int remainingDepth;
  uint4 PRNGStates;
  float4 color;
  float hitT;
};

struct AttributeData
{
  float2 barycentrics;
};
//https://zhuanlan.zhihu.com/p/84413439
//采样随即透镜的点然后使用屏幕uv映射
inline void GenerateFocusCameraRayWithOffset(out float3 origin, out float3 direction, float2 apertureOffset, float2 offset)
{
  float2 xy = DispatchRaysIndex().xy + offset;
  float2 uv = xy / DispatchRaysDimensions().xy;

  float3 world = _FocusCameraLeftBottomCorner + uv.x * _FocusCameraSize.x * _FocusCameraRight + uv.y * _FocusCameraSize.y * _FocusCameraUp;

  origin = _WorldSpaceCameraPos.xyz + _FocusCameraHalfAperture * apertureOffset.x * _FocusCameraRight + _FocusCameraHalfAperture * apertureOffset.y * _FocusCameraUp;
  direction = normalize(world.xyz - origin);
}