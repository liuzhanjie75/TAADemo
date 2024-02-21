using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace TAA
{
    public class TAA : ScriptableRendererFeature
    {
        [SerializeField] public float JitterScale = 1f;
        [SerializeField] public Material TaaMaterial;
        
        private JitterPass _jitterPass;
        private TAAPass _taaPass;

        public override void Create()
        {
            _jitterPass ??= new JitterPass
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques
            };

            _taaPass ??= new TAAPass()
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
            };
            
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.postProcessEnabled || TaaMaterial == null) 
                return;
            
            var shouldAdd = _jitterPass.Setup(JitterScale) && _taaPass.Setup(JitterScale, ref TaaMaterial);
            if (!shouldAdd) 
                return;
            
            renderer.EnqueuePass(_jitterPass);
            renderer.EnqueuePass(_taaPass);
        }

        protected override void Dispose(bool disposing) 
        {
            _jitterPass?.Dispose();
            _taaPass?.Dispose();
            _taaPass = null;
        }
        

        private class TAAPass : ScriptableRenderPass
        {
            private float _jitterScale = 1f;
            private Material _taaMaterial;
            private readonly ProfilingSampler _profilingSampler = new("TAA");
            private RenderTextureDescriptor _taaDescriptor;
            private RTHandle _sourceTexture;
            private RTHandle _destinationTexture;
            private RTHandle _taaTexture0;
            private RTHandle _taaTexture1;
            private RTHandle _accumulationTexture;
            private RTHandle _taaTemporaryTexture;

            private const string AccumulationTextureName = "_TaaAccumulationTexture";
            private const string TaaTemporaryTextureName = "_TaaTemporaryTexture";
            private const string TAATexture0Name = "_TAATexture0";
            private const string TAATexture1Name = "_TAATexture1";

            private bool _resetHistoryFrames;
            
            private static readonly int TaaAccumulationTexID = Shader.PropertyToID("_TaaAccumulationTexture");
            private static readonly int SourceSize = Shader.PropertyToID("_SourceSize");
            
            internal bool Setup(float jitterScale, ref Material material) {
                _taaMaterial = material;
                _jitterScale = jitterScale;

                ConfigureInput(ScriptableRenderPassInput.Normal);

                return _taaMaterial != null;
            }
            
            public void Dispose()
            {
                _accumulationTexture?.Release();
                _accumulationTexture = null;

                _taaTemporaryTexture?.Release();
                _taaTemporaryTexture = null;
            }
            
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (_taaMaterial == null)
                {
                    Debug.LogErrorFormat("{0}.Execute(): Missing material. ScreenSpaceAmbientOcclusion pass will not execute. Check for missing reference in the renderer resources.", GetType().Name);
                    return;
                }

                var commandBuffer = CommandBufferPool.Get();
                context.ExecuteCommandBuffer(commandBuffer);
                commandBuffer.Clear();

                _sourceTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                _destinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;

                using (new ProfilingScope(commandBuffer, _profilingSampler))
                {
                    commandBuffer.SetGlobalTexture(TaaAccumulationTexID, _accumulationTexture);
                    commandBuffer.SetGlobalFloat("_FrameInfluence", _resetHistoryFrames ? 1f : 0.1f);
                    
                    Blitter.BlitCameraTexture(commandBuffer, _sourceTexture, _taaTemporaryTexture, _taaMaterial, 0);
                    
                    Blitter.BlitCameraTexture(commandBuffer, _taaTemporaryTexture, _accumulationTexture);
                    
                    Blitter.BlitCameraTexture(commandBuffer, _taaTemporaryTexture, _destinationTexture);

                    _resetHistoryFrames = false;
                }
                
                context.ExecuteCommandBuffer(commandBuffer);
                CommandBufferPool.Release(commandBuffer);
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                base.OnCameraSetup(cmd, ref renderingData);

                _taaDescriptor = renderingData.cameraData.cameraTargetDescriptor;
                _taaDescriptor.msaaSamples = 1;
                _taaDescriptor.depthBufferBits = 0;
                
                _taaMaterial.SetVector(SourceSize, new Vector4(_taaDescriptor.width,_taaDescriptor.height, 1.0f / _taaDescriptor.width, 1.0f / _taaDescriptor.height ));
                _resetHistoryFrames = RenderingUtils.ReAllocateIfNeeded(ref _accumulationTexture, _taaDescriptor,
                    FilterMode.Bilinear, TextureWrapMode.Clamp, name: AccumulationTextureName);
                
                RenderingUtils.ReAllocateIfNeeded(ref _taaTemporaryTexture, _taaDescriptor, FilterMode.Bilinear,
                    TextureWrapMode.Clamp, name: TaaTemporaryTextureName);

                var renderer = renderingData.cameraData.renderer;
                ConfigureTarget(renderer.cameraColorTargetHandle);
                ConfigureClear(ClearFlag.None, Color.white);
                
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                base.OnCameraCleanup(cmd);

                _sourceTexture = null;
                _destinationTexture = null;
            }
        }
        private class JitterPass : ScriptableRenderPass
        {
            private float _jitterScale = 1f;
            private readonly ProfilingSampler _profilingSampler = new("Jitter");

            public bool Setup(float jitterScale)
            {
                _jitterScale = jitterScale;
                return true;
            }
            
            public void Dispose()
            {
            }
            
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var commandBuffer = CommandBufferPool.Get();
                context.ExecuteCommandBuffer(commandBuffer);
                commandBuffer.Clear();

                using (new ProfilingScope(commandBuffer, _profilingSampler))
                {
                    commandBuffer.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(),
                        Jitter.CalculateJitterProjectionMatrix(ref renderingData.cameraData, _jitterScale));
                }
                
                context.ExecuteCommandBuffer(commandBuffer);
                CommandBufferPool.Release(commandBuffer);
            }
        }
    }
}

