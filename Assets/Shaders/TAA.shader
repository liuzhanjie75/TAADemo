Shader "AA/TAA"
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
            float4x4 _ViewProjMatrixWithoutJitter;
            float4x4 _LastViewProjMatrix;
            static const int kOffsetSize = 9;
            static const int2 kOffsets3x3[kOffsetSize] =
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
                for (int k = 0; k < kOffsetSize; ++k)
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

                return lerp(accm, filtered, clipBlend);
            }

            float2 ComputeVelocity(float2 uv)
            {
                float depth = SampleSceneDepth(uv).x;
                #if !UNITY_REVERSED_Z  
                depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(uv).x);  
                #endif

                // 还原本帧和上帧没有Jitter的裁剪坐标 
                float3 posWS = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
                float4 posCS = mul(_ViewProjMatrixWithoutJitter, float4(posWS.xyz, 1.0));
                float4 prevPosCS = mul(_LastViewProjMatrix, float4(posWS.xyz, 1.0));

                // 计算出本帧和上帧没有Jitter的NDC坐标 [-1, 1]
                float2 posNDC = posCS.xy * rcp(posCS.w);
                float2 prevPosNDC = prevPosCS.xy * rcp(prevPosCS.w);

                // 计算NDC位置差
                float2 velocity = posNDC - prevPosNDC;
                #if UNITY_UV_STARTS_AT_TOP  
                velocity.y = -velocity.y;  
                #endif

                // 将速度从[-1, 1]映射到[0, 1]  
                // ((posNDC * 0.5 + 0.5) - (prevPosNDC * 0.5 + 0.5)) = (velocity * 0.5)    velocity.xy *= 0.5;
                
                return velocity;
            }

            float2 AdjustBestDepthOffset(float2 uv)
            {
                float bestDepth = 1.0f;
                float2 uvOffset = 0.0f;

                UNITY_LOOP
                for (int k = 0; k < kOffsetSize; ++k)
                {
                    half depth = SampleSceneDepth(uv + kOffsets3x3[k] * _SourceSize.zw);
                    #if UNITY_REVERSED_Z
                    depth = 1.0 - depth;
                    #endif

                    if (depth < bestDepth)
                    {
                        bestDepth = depth;
                        uvOffset = kOffsets3x3[k] * _SourceSize.zw;
                    }
                }

                return uvOffset;
            }

            half4 TAAPassFragment(Varyings input) : SV_Target
            {
                float2 depthOffsetUV = AdjustBestDepthOffset(input.texcoord);
                float2 velocity = ComputeVelocity(input.texcoord + depthOffsetUV);
                float2 historyUV = input.texcoord - velocity;
                
                float4 accum = GetAccumulation(historyUV);
                float4 source = GetSource(input.texcoord);

                const float3 historyYCoCg = RGBToYCoCg(accum.rgb);
                half3 boxMin;
                half3 boxMax;
                AdjustColorBox(input.texcoord, boxMin, boxMax);

                //accum.rgb = YCoCgToRGB(clamp(historyYCoCg, boxMin, boxMax));
                accum.rgb = YCoCgToRGB(ClipToAABBCenter(historyYCoCg, boxMin, boxMax));
                float frameInfluence = saturate(_FrameInfluence + length(velocity) * 100);

                return accum * (1.0 - frameInfluence) + source * frameInfluence;
            }
            
            #endif
            ENDHLSL
        }
    }
}
