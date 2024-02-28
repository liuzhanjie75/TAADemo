Shader "AA/SMAA"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    
    SubShader
    {
         
        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment FragEdge

            // Edge Detection
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _SourceSize;

            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }


            float4 FragEdge(Varyings i) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragBlend

            // Blend Weights Calculation
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _SourceSize;


            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }

            float4 FragBlend(Varyings i) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragNeighbor

            // Neighborhood Blending
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _SourceSize;
            Texture2D _BlendTex;

            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }

            float4 FragNeighbor(Varyings i) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
}
