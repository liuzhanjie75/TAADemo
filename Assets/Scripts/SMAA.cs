using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SMAA : ScriptableRendererFeature
{
    
    [SerializeField] public Material SMAAMaterial;

    private SMAAPass _SMAAPass;

    public override void Create()
    {
        _SMAAPass ??= new SMAAPass()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (_SMAAPass.Setup(SMAAMaterial))
            renderer.EnqueuePass(_SMAAPass);
    }
    
    protected override void Dispose(bool disposing) 
    {
        _SMAAPass?.Dispose(disposing);
        _SMAAPass = null;
    }
    
    private class SMAAPass : ScriptableRenderPass
    {
        private Material _SMAAMaterial;
        private RTHandle _sourceTexture;
        private RTHandle _edgeTexture;
        private RTHandle _blendTexture;
        private RenderTextureDescriptor _SMAADescriptor;
        
        private readonly ProfilingSampler _profilingSampler = new("SMAA");
        private const string SourceTexture = "_sourceTexture";
        private const string EdgeTexture = "_edgeTexture";
        private const string BlendTexture = "_blendTexture";
        private static readonly int SourceSize = Shader.PropertyToID("_SourceSize");
        private static readonly int BlendTex = Shader.PropertyToID("_BlendTex");
        public bool Setup(Material fxaa)
        {
            _SMAAMaterial = fxaa;
            ConfigureInput(ScriptableRenderPassInput.Normal);
            return _SMAAMaterial != null;
        }

        public void Dispose(bool disposing)
        {
            _edgeTexture?.Release();
            _edgeTexture = null;
            _blendTexture?.Release();
            _blendTexture = null;
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_SMAAMaterial == null)
                return;

            var commandBuffer = CommandBufferPool.Get();
            context.ExecuteCommandBuffer(commandBuffer);
            commandBuffer.Clear();

            using (new ProfilingScope(commandBuffer, _profilingSampler))
            {
                _SMAAMaterial.hideFlags = HideFlags.HideAndDontSave;
                var sourceTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                var destinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                
                _SMAAMaterial.SetVector(SourceSize,
                    new Vector4(_SMAADescriptor.width, _SMAADescriptor.height, 1.0f / _SMAADescriptor.width,
                        1.0f / _SMAADescriptor.height));
                
                Blitter.BlitCameraTexture(commandBuffer, sourceTexture, _sourceTexture);
                Blitter.BlitCameraTexture(commandBuffer, sourceTexture, _edgeTexture, _SMAAMaterial, 0);
                Blitter.BlitCameraTexture(commandBuffer, _edgeTexture, _blendTexture, _SMAAMaterial, 1);
                _SMAAMaterial.SetTexture(BlendTex, _blendTexture);
                Blitter.BlitCameraTexture(commandBuffer, _sourceTexture, destinationTexture, _SMAAMaterial, 2);

            }
            
            context.ExecuteCommandBuffer(commandBuffer);
            CommandBufferPool.Release(commandBuffer);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            base.OnCameraSetup(cmd, ref renderingData);
            _SMAADescriptor = renderingData.cameraData.cameraTargetDescriptor;
            _SMAADescriptor.msaaSamples = 1;
            _SMAADescriptor.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref _sourceTexture, _SMAADescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: SourceTexture);
            
            _SMAADescriptor.colorFormat = RenderTextureFormat.RG16;
            RenderingUtils.ReAllocateIfNeeded(ref _edgeTexture, _SMAADescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: EdgeTexture);
            
            _SMAADescriptor.colorFormat = RenderTextureFormat.BGRA32;
            RenderingUtils.ReAllocateIfNeeded(ref _blendTexture, _SMAADescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: BlendTexture);

            var renderer = renderingData.cameraData.renderer;
            ConfigureTarget(renderer.cameraColorTargetHandle);
            ConfigureClear(ClearFlag.None, Color.white);
        }
    }
}
