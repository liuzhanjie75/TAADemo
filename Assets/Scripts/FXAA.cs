using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class FXAA : ScriptableRendererFeature
{
    public enum FXAAMode
    {
        Quality = 0,
        Console = 1,
    };
    
    [SerializeField] public Shader FxaaShader;
    [SerializeField] public FXAAMode Mode;
    [Range(0.0312f, 0.0833f)]
    public float contrastThreshold = 0.0312f;
    [Range(0.063f, 0.333f)]
    public float relativeThreshold = 0.063f;

    private FxaaPass _fxaaPass;

    public override void Create()
    {
        _fxaaPass ??= new FxaaPass()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.postProcessEnabled || FxaaShader == null) 
            return;
        
        if (_fxaaPass.Setup(FxaaShader, Mode, contrastThreshold, relativeThreshold))
            renderer.EnqueuePass(_fxaaPass);
    }
    
    protected override void Dispose(bool disposing) 
    {
        _fxaaPass?.Dispose(disposing);
        _fxaaPass = null;
    }
    
    private class FxaaPass : ScriptableRenderPass
    {
        private Material _fxaaMaterial;
        private FXAAMode _mode;
        private float _contrastThreshold = 0.0312f;
        private float _relativeThreshold = 0.063f;
        private RTHandle _fxaaTexture;
        private RenderTextureDescriptor _fxaaDescriptor;
        
        private readonly ProfilingSampler _profilingSampler = new("FXAA");
        private const string FxaaTexture = "_FxaaTexture";
        private static readonly int SourceSize = Shader.PropertyToID("_SourceSize");
        private static readonly int ContrastThreshold = Shader.PropertyToID("_ContrastThreshold");
        private static readonly int RelativeThreshold = Shader.PropertyToID("_RelativeThreshold");
        public bool Setup(Shader fxaa, FXAAMode mode, float contrastThreshold, float relativeThreshold)
        {
            _fxaaMaterial = new Material(fxaa);
            _mode = mode;
            _contrastThreshold = contrastThreshold;
            _relativeThreshold = relativeThreshold;
            ConfigureInput(ScriptableRenderPassInput.Normal);
            return _fxaaMaterial != null;
        }

        public void Dispose(bool disposing)
        {
            _fxaaTexture?.Release();
            _fxaaTexture = null;
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_fxaaMaterial == null)
                return;

            var commandBuffer = CommandBufferPool.Get();
            context.ExecuteCommandBuffer(commandBuffer);
            commandBuffer.Clear();

            using (new ProfilingScope(commandBuffer, _profilingSampler))
            {
                _fxaaMaterial.hideFlags = HideFlags.HideAndDontSave;
                var sourceTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                var destinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;

                _fxaaMaterial.SetFloat(ContrastThreshold, _contrastThreshold);
                _fxaaMaterial.SetFloat(RelativeThreshold, _relativeThreshold);
                _fxaaMaterial.SetVector(SourceSize,
                    new Vector4(_fxaaDescriptor.width, _fxaaDescriptor.height, 1.0f / _fxaaDescriptor.width,
                        1.0f / _fxaaDescriptor.height));
                
                Blitter.BlitCameraTexture(commandBuffer, sourceTexture, _fxaaTexture, _fxaaMaterial, (int)_mode);
                Blitter.BlitCameraTexture(commandBuffer, _fxaaTexture, destinationTexture);
            }
            
            context.ExecuteCommandBuffer(commandBuffer);
            CommandBufferPool.Release(commandBuffer);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            base.OnCameraSetup(cmd, ref renderingData);
            _fxaaDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            _fxaaDescriptor.msaaSamples = 1;
            _fxaaDescriptor.depthBufferBits = 0;
            
            RenderingUtils.ReAllocateIfNeeded(ref _fxaaTexture, _fxaaDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: FxaaTexture);

            var renderer = renderingData.cameraData.renderer;
            ConfigureTarget(renderer.cameraColorTargetHandle);
            ConfigureClear(ClearFlag.None, Color.white);
        }
    }
}
