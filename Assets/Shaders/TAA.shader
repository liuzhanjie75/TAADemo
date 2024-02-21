Shader "Unlit/TAA"
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
            #pragma fragment TAAPassFragment
            
            #ifndef _SSR_PASS_INCLUDED
            #define _SSR_PASS_INCLUDED

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_TaaAccumulationTexture);
            SAMPLER(sampler_TaaAccumulationTexture);

            float _FrameInfluence;
            float4 _SourceSize;
            static const int2 kOffsets3x3[9] =
            {
	            int2(-1, -1),
	            int2( 0, -1),
	            int2( 1, -1),
	            int2(-1,  0),
                int2( 0,  0),
	            int2( 1,  0),
	            int2(-1,  1),
	            int2( 0,  1),
	            int2( 1,  1),
            };

            half4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }

            half4 GetAccumulation(half2 uv)
            {  
                return SAMPLE_TEXTURE2D(_TaaAccumulationTexture, sampler_LinearClamp, uv);  
            }

            void AdjustColorBox(float2 uv, inout half3 boxMin, inout half3 boxMax)
            {
                boxMax = 1.0;
                boxMin = 0.0;

                UNITY_UNROLL
                for (int k = 0; k < 9; ++k)
                {
                    float3 c = RGBToYCoCg(GetSource(uv + kOffsets3x3[k] * _SourceSize.zw));
                    boxMin = min(boxMin, c);
                    boxMax = max(boxMax, c);
                }
            }

            float3 ClipToAABBCenter(half3 accm, half3 boxMin, half3 boxMax)
            {
                //accm = RGBToYCoCg(accm);
                float3 filtered = (boxMin + boxMax) * 0.5f;
                float3 origin = accm;
                float3 dir = filtered - accm;
                dir = abs(dir) < (1.0f / 65536.0f) ? (1.0f / 65536.0f) : dir;
                float3 invDir = rcp(dir);

                // 获取与box相交的位置
                float3 minIntersect = (boxMin - origin) * invDir;
                float3 maxIntersect = (boxMax - origin) * invDir;
                float3 enterIntersect = min(minIntersect, maxIntersect);
                float clipBlend = max(enterIntersect.x, max(enterIntersect.y, enterIntersect.z));
                clipBlend = saturate(clipBlend);

                return YCoCgToRGB(lerp(accm, filtered, clipBlend));
            }

            half4 TAAPassFragment(Varyings input) : SV_Target
            {
                float4 accum = GetAccumulation(input.texcoord);
                float4 source = GetSource(input.texcoord);

                const float3 historyYCoCg = RGBToYCoCg(accum.rgb);
                half3 boxMin;
                half3 boxMax;
                AdjustColorBox(input.texcoord, boxMin, boxMax);

                //accum.rgb = YCoCgToRGB(clamp(historyYCoCg, boxMin, boxMax));
                accum.rgb = ClipToAABBCenter(historyYCoCg, boxMin, boxMax);

                return accum * (1.0 - _FrameInfluence) + source * _FrameInfluence;
            }
            
            #endif
            ENDHLSL
        }
    }
}
