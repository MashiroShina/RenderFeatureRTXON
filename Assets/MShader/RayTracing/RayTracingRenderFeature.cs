using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RayTracingRenderFeature : ScriptableRendererFeature
{
    /// <summary>
    /// PropertyToID
    /// </summary>
    /// ================================================================================
    protected static readonly int _outputTargetShaderId = Shader.PropertyToID("_OutputTarget");
    private static readonly int _PRNGStatesShaderId = Shader.PropertyToID("_PRNGStates");
    private static readonly int _frameIndexShaderId = Shader.PropertyToID("_FrameIndex");

    public static readonly int accelerationStructureShaderId = Shader.PropertyToID("_AccelerationStructure");
    public static readonly int _WorldSpaceCameraPos = Shader.PropertyToID("_WorldSpaceCameraPos");
    public static readonly int _InvCameraViewProj = Shader.PropertyToID("_InvCameraViewProj");
    public static readonly int _CameraFarDistance = Shader.PropertyToID("_CameraFarDistance");

    public static readonly int _FocusCameraLeftBottomCorner = Shader.PropertyToID("_FocusCameraLeftBottomCorner");
    public static readonly int _FocusCameraRight = Shader.PropertyToID("_FocusCameraRight");
    public static readonly int _FocusCameraUp = Shader.PropertyToID("_FocusCameraUp");
    public static readonly int _FocusCameraSize = Shader.PropertyToID("_FocusCameraSize");
    public static readonly int _FocusCameraHalfAperture = Shader.PropertyToID("_FocusCameraHalfAperture");
    /// ================================================================================
    private static readonly Dictionary<int, RTHandle> _outputTargets = new Dictionary<int, RTHandle>();
    private static readonly Dictionary<int, ComputeBuffer> _PRNGStates = new Dictionary<int, ComputeBuffer>();
    protected static RTHandle RequireOutputTarget(Camera camera)
    {
        var id = camera.GetInstanceID();

        if (_outputTargets.TryGetValue(id, out var outputTarget))
            return outputTarget;

        outputTarget = RTHandles.Alloc(
          camera.pixelWidth,
          camera.pixelHeight,
          1,
          DepthBits.None,
          GraphicsFormat.R32G32B32A32_SFloat,
          FilterMode.Point,
          TextureWrapMode.Clamp,
          TextureDimension.Tex2D,
          true,
          false,
          false,
          false,
          1,
          0f,
          MSAASamples.None,
          false,
          false,
          RenderTextureMemoryless.None,
          $"OutputTarget_{camera.name}");
        _outputTargets.Add(id, outputTarget);

        return outputTarget;
    }
    public static ComputeBuffer RequirePRNGStates(Camera camera)
    {
        var id = camera.GetInstanceID();
        if (_PRNGStates.TryGetValue(id, out var buffer))
            return buffer;

        buffer = new ComputeBuffer(camera.pixelWidth * camera.pixelHeight, 4 * 4, ComputeBufferType.Structured, ComputeBufferMode.Immutable);

        var _mt19937 = new MersenneTwister.MT.mt19937ar_cok_opt_t();
        _mt19937.init_genrand((uint)System.DateTime.Now.Ticks);

        var data = new uint[camera.pixelWidth * camera.pixelHeight * 4];
        for (var i = 0; i < camera.pixelWidth * camera.pixelHeight * 4; ++i)
            data[i] = _mt19937.genrand_int32();
        buffer.SetData(data);

        _PRNGStates.Add(id, buffer);
        return buffer;
    }

    private static RayTracingAccelerationStructure _maccelerationStructure;

    class RayTracingPass : ScriptableRenderPass
    {
        public Material FinalBlitMat;
        public Material denoiseMat;
        public float DenoiseStrength;

        public RayTracingPass(RayTracingShader _shader,ref RayTracingAccelerationStructure accStruct)
        {
            rayTracingShader = _shader;
            _maccelerationStructure = accStruct;
        }
        static  RayTracingShader rayTracingShader;
        string m_ProfilerTag = "RayTracingOutPutPass";
  
        private int _frameIndex = 0;

        private  RenderTargetIdentifier source { get; set; }
        private RenderTargetHandle destination { get; set; }

        private static Vector3 leftBottomCorner;
        private static Vector2 size;
        private static Vector2 mfocusDistanceAndaperture;
        private static void SetupCamera(Camera camera)
        {
            Shader.SetGlobalVector(_WorldSpaceCameraPos, camera.transform.position);
            var projMatrix = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
            var viewMatrix = camera.worldToCameraMatrix;
            var viewProjMatrix = projMatrix * viewMatrix;
            var invViewProjMatrix = Matrix4x4.Inverse(viewProjMatrix);
            Shader.SetGlobalMatrix(_InvCameraViewProj, invViewProjMatrix);
            Shader.SetGlobalFloat(_CameraFarDistance, camera.farClipPlane);
        }
        private static void setFocAndAperture(Camera camera,float focusDistance,float aperture,CommandBuffer cmd) {
            var theta = camera.fieldOfView * Mathf.Deg2Rad;
            var halfHeight = Mathf.Tan(theta * 0.5f);
            var halfWidth = camera.aspect * halfHeight;
            leftBottomCorner = camera.transform.position + camera.transform.forward * focusDistance -
                               camera.transform.right * focusDistance * halfWidth -
                               camera.transform.up * focusDistance * halfHeight;
            size = new Vector2(focusDistance * halfWidth * 2.0f, focusDistance * halfHeight * 2.0f);

            cmd.SetRayTracingVectorParam(rayTracingShader, _FocusCameraLeftBottomCorner, leftBottomCorner);
            cmd.SetRayTracingVectorParam(rayTracingShader, _FocusCameraRight, camera.transform.right);
            cmd.SetRayTracingVectorParam(rayTracingShader, _FocusCameraUp, camera.transform.up);
            cmd.SetRayTracingVectorParam(rayTracingShader, _FocusCameraSize, size);
            cmd.SetRayTracingFloatParam(rayTracingShader, _FocusCameraHalfAperture, aperture * 0.5f);
        }
        public void Setup(RenderTargetIdentifier source, RenderTargetHandle destination,Camera camera, Vector2 focusDistanceAndaperture )
        {
            this.source = source;
            this.destination = destination;
            SetupCamera(camera);
            mfocusDistanceAndaperture = focusDistanceAndaperture;
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
   
        }
        private void SetSkyBox(CommandBuffer cb,RayTracingShader rayTracingShader) {
            string shaderName = "";
            if (RenderSettings.skybox != null)
            {
                shaderName = RenderSettings.skybox.shader.name;
            }
            if (shaderName == "Skybox/Panoramic")
            {
                cb.SetRayTracingIntParam(rayTracingShader, "_Procedural", 0);
                Texture tex = RenderSettings.skybox.GetTexture("_MainTex");
                if (tex == null) tex = Texture2D.whiteTexture;
                cb.SetRayTracingTextureParam(rayTracingShader, "_Skybox", tex);
                cb.SetRayTracingVectorParam(rayTracingShader, "_Tint", RenderSettings.skybox.GetColor("_Tint"));
                cb.SetRayTracingFloatParam(rayTracingShader, "_Exposure", RenderSettings.skybox.GetFloat("_Exposure"));
                cb.SetRayTracingFloatParam(rayTracingShader, "_Rotation", RenderSettings.skybox.GetFloat("_Rotation"));
                cb.SetRayTracingVectorParam(rayTracingShader, "_MainTex_HDR", RenderSettings.skybox.GetVector("_MainTex_HDR"));
            }
            else
            {
                cb.SetRayTracingIntParam(rayTracingShader, "_Procedural", 1);
                cb.SetRayTracingTextureParam(rayTracingShader, "_Skybox", Texture2D.blackTexture);
                cb.SetRayTracingVectorParam(rayTracingShader, "_Tint", new Vector4(103, 128, 165) / 256);
                cb.SetRayTracingVectorParam(rayTracingShader, "_MainTex_HDR", new Vector4(107, 91, 58) / 256);
            }
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            
            
            _maccelerationStructure.Update();
            ref CameraData cameraData = ref renderingData.cameraData;
            var outputTarget = RequireOutputTarget(cameraData.camera);
            var PRNGStates = RequirePRNGStates(cameraData.camera);
            int TempDenoise = Shader.PropertyToID("_DenoiseTemp");
            cmd.GetTemporaryRT(TempDenoise, renderingData.cameraData.camera.pixelWidth, renderingData.cameraData.camera.pixelHeight,
                0, FilterMode.Point, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear, 1, true);

            using (new ProfilingSample(cmd, "RayTracing")) {
                if (Camera.main.transform.hasChanged)
                {
                    _frameIndex = 0;
                    Camera.main.transform.hasChanged = false;
                }
  
                if (_frameIndex < 10000)
                {
                    setFocAndAperture(cameraData.camera, mfocusDistanceAndaperture.x, mfocusDistanceAndaperture.y, cmd);
                    cmd.SetRayTracingShaderPass(rayTracingShader, "RayTracing");
                    SetSkyBox(cmd, rayTracingShader);
                    cmd.SetRayTracingAccelerationStructure(rayTracingShader, accelerationStructureShaderId, _maccelerationStructure);
                    cmd.SetRayTracingIntParam(rayTracingShader, _frameIndexShaderId, _frameIndex);
                    cmd.SetRayTracingBufferParam(rayTracingShader, _PRNGStatesShaderId, PRNGStates);
                    cmd.SetRayTracingTextureParam(rayTracingShader, _outputTargetShaderId, outputTarget);
                    cmd.SetGlobalVector("_Pixel_WH", 
                        new Vector4(renderingData.cameraData.camera.pixelWidth, renderingData.cameraData.camera.pixelHeight));

                    cmd.DispatchRays(rayTracingShader, "OutputColorRayGenShader", (uint)outputTarget.rt.width, (uint)outputTarget.rt.height, 1, cameraData.camera);
                }
                using (new ProfilingSample(cmd, "FinalBlit"))
                {
                        if (cameraData.camera.cameraType == CameraType.Game)
                        {
                            _frameIndex++;
                            cmd.SetGlobalTexture(Shader.PropertyToID("_TempRTSceneTex"), outputTarget);
                            cmd.Blit(outputTarget, source, FinalBlitMat);
                            cmd.SetGlobalFloat("_DenoiseStrength", DenoiseStrength * 0.1f);
                            cmd.Blit(source, TempDenoise, denoiseMat, 0);
                            cmd.SetGlobalTexture(Shader.PropertyToID("_TempDebug"), TempDenoise);
                            cmd.Blit(TempDenoise, source);
                        }
                        else
                        {
                            cmd.Blit(outputTarget, BuiltinRenderTextureType.CameraTarget, Vector2.one, Vector2.zero);
                        }
                }
            }
            context.ExecuteCommandBuffer(cmd);
           
            CommandBufferPool.Release(cmd);

        }

        /// Cleanup any allocated resources that were created during the execution of this render pass.
        public override void FrameCleanup(CommandBuffer cmd)
        {
        }
        ~RayTracingPass()
        {
            foreach (var pair in _PRNGStates)
            {
                pair.Value.Release();
            }
            _PRNGStates.Clear();

            foreach (var pair in _outputTargets)
            {
                pair.Value.Release();
            }
            _outputTargets.Clear();
            if (_maccelerationStructure!=null)
            {
                _maccelerationStructure.Release();
                _maccelerationStructure = null;
            }
        }
    }


    [System.Serializable]
    public class RayTraceSettings
    {
        public RayTracingShader _shader ;
        public RenderPassEvent mrenderPassEvent = RenderPassEvent.AfterRendering;
        [Range(0,10)]
        public float focusDistance, aperture;
        public  Material FinalBlitMat;
        public Material denoiseMat;
        [Range(0.01f,5)]
        public float DenoiseStrength;
    }
    public RayTraceSettings settings = new RayTraceSettings();
    RayTracingPass mRayTracingPass;
    RayTracingAccelerationStructure _accelerationStructure;
    public override void Create()
    {
        if (_accelerationStructure!=null)
        {
            _accelerationStructure.Dispose();
            _accelerationStructure.Release();
        }
        RayTracingAccelerationStructure.RASSettings setting = new RayTracingAccelerationStructure.RASSettings
            (RayTracingAccelerationStructure.ManagementMode.Automatic, RayTracingAccelerationStructure.RayTracingModeMask.Everything,  -1^(1 << 7));
        _accelerationStructure = new RayTracingAccelerationStructure(setting);
        _accelerationStructure.Build();

        mRayTracingPass = new RayTracingPass(settings._shader,ref  _accelerationStructure);
        mRayTracingPass.FinalBlitMat = settings.FinalBlitMat; ;
        mRayTracingPass.denoiseMat = settings.denoiseMat;
        mRayTracingPass.DenoiseStrength = settings.DenoiseStrength;
        mRayTracingPass.renderPassEvent = settings.mrenderPassEvent;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        //renderer.cameraColorTarget 是当前相机拍摄的东西，无论任何queue都直接生效
        // RenderTargetHandle.CameraTarget则是一张在renderpass后的rt,只会在指定rtpss后让相机生效
        mRayTracingPass.Setup(renderer.cameraColorTarget, RenderTargetHandle.CameraTarget,renderingData.cameraData.camera,new Vector2(settings.focusDistance,settings.aperture));
        renderer.EnqueuePass(mRayTracingPass);
    }
}


