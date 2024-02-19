using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace TAA
{
    [SerializeField]
    internal class TAASettings
    {
        [SerializeField] internal float JitterScale = 10f;
    }
    public class TAA : ScriptableRendererFeature
    {
        [SerializeField] private TAASettings Settings = new();
        private JitterPass _jitterPass;
        
        public override void Create()
        {
            _jitterPass ??= new JitterPass
            {
                renderPassEvent = RenderPassEvent.AfterRenderingOpaques
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.postProcessEnabled)
            {
                var shouldAdd = _jitterPass.Setup(Settings);
                if (shouldAdd)
                    renderer.EnqueuePass(_jitterPass);
            }
        }
        
        protected override void Dispose(bool disposing) 
        {
            _jitterPass?.Dispose();
        }

        private class JitterPass : ScriptableRenderPass
        {
            private TAASettings _settings;
            private readonly ProfilingSampler _profilingSampler = new("Jitter");

            public bool Setup(TAASettings settings)
            {
                _settings = settings;
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
                    commandBuffer.SetViewProjectionMatrices(renderingData.cameraData.GetProjectionMatrix(),
                        Jitter.CalculateJitterProjectionMatrix(ref renderingData.cameraData, _settings.JitterScale));
                }
                
                context.ExecuteCommandBuffer(commandBuffer);
                CommandBufferPool.Release(commandBuffer);
            }
        }
    }
}

