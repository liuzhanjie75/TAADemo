Shader "AA/FXAA"
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
            #pragma fragment FXAAQualityFragement

            // FXAA QUALITY版本
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _SourceSize;
            float _ContrastThreshold;
            float _RelativeThreshold;

            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }

            float4 FXAAQualityFragement(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 TexelSize = _SourceSize.zw;
                float4 origin = GetSource(uv);
                float M = Luminance(origin);
                float E = Luminance(GetSource(uv + float2(TexelSize.x, 0)));
                float N = Luminance(GetSource(uv + float2(0, TexelSize.y)));
                float W = Luminance(GetSource(uv + float2(-TexelSize.x, 0)));
                float S = Luminance(GetSource(uv + float2(0, -TexelSize.y)));
                float NW = Luminance(GetSource(uv + float2(-TexelSize.x, TexelSize.y)));
                float NE = Luminance(GetSource(uv + float2(TexelSize.x, TexelSize.y)));
                float SW = Luminance(GetSource(uv + float2(-TexelSize.x, -TexelSize.y)));
                float SE = Luminance(GetSource(uv + float2(TexelSize.x, -TexelSize.y)));

                //计算出对比度的值
                float maxLuma = max(max(max(N,E), max(W, S)), M);
                float minLuma = min(min(min(N,E), min(W, S)), M);
                float contrast = maxLuma - minLuma;

                //如果对比度值很小，认为不需要进行抗锯齿，直接跳过抗锯齿计算
                if (contrast < max(_ContrastThreshold, maxLuma * _RelativeThreshold))
                    return origin;

                // 先计算出锯齿的方向，是水平还是垂直方向
                float vertical = abs(N + S - 2 * M) * 2 + abs(NE + SE - 2 * E) + abs(NW + SW - 2 * W);
                float horizontal = abs(E + W - 2 * M) * 2 + abs(NE + NW - 2 * N) + abs(SE + SW - 2 * S);
                bool isHorizontal = vertical > horizontal;
                // 混和的方向
                float2 pixelStep = isHorizontal ? float2(0, TexelSize.y) : float2(TexelSize.x, 0);
                // 确定混合方向的符号
                float positive = abs((isHorizontal ? N : E) - M);
                float negative = abs((isHorizontal ? S : W) - M);
                // 算出锯齿两侧的亮度变化的梯度值
                float gradient = 0;
                float oppositeLunminance = 0;
                if (positive > negative)
                {
                    gradient = positive;
                    oppositeLunminance = isHorizontal ? N : E;
                }
                else
                {
                    pixelStep = -pixelStep;
                    gradient = negative;
                    oppositeLunminance = isHorizontal ? S : W;
                }
                
                // 计算基于亮度的混合系数
                float filter = 2 * (N + E + S + W) + NE + NW + SE + SW;
                filter = filter / 12;
                filter = abs(filter - M);
                filter = saturate(filter / contrast);
                
                // 基于亮度的混合系数值
                float pixelBlend = smoothstep(0, 1, filter);
                pixelBlend = pixelBlend * pixelBlend;

                // 基于边界的混合系数计算
                float2 uvEdge = uv + pixelStep * 0.5f;
                float2 edgeStep = isHorizontal ? float2(TexelSize.x, 0) : float2(0, TexelSize.y);
                
                // 这里是定义搜索的步长，步长越长，效果自然越好
			    const float _SearchSteps = 15;
			    // 未搜索到边界时，猜测的边界距离
			    const float _Guess = 8;
			    
			    // 沿着锯齿边界两侧，进行搜索，找到锯齿的边界
			    float edgeLuminance = (M + oppositeLunminance) * 0.5f;
                float gradientThreshold = gradient * 0.25f;
                float pLuminanceDelta = 0;
                float pDistance = 0;

                UNITY_LOOP
                int i = 0;
                for (i = 1; i <= _SearchSteps; ++i)
                {
                    pLuminanceDelta = Luminance(GetSource(uvEdge + i * edgeStep)) - edgeLuminance;
                    if (abs(pLuminanceDelta) > gradientThreshold)
                    {
                        pDistance = i * (isHorizontal ? edgeStep.x : edgeStep.y);
                        break;
                    }
                }
                if (i == _SearchSteps + 1)
                {
                    pDistance = edgeStep * _Guess;
                }
                
                float nLuminanceDelta = 0;
                float nDistance = 0;
                UNITY_LOOP
                for (i = 1; i <= _SearchSteps; ++i)
                {
                    nLuminanceDelta = Luminance(GetSource(uvEdge + i * edgeStep)) - edgeLuminance;
                    if (abs(nLuminanceDelta) > gradientThreshold)
                    {
                        nDistance = i * (isHorizontal ? edgeStep.x : edgeStep.y);
                        break;
                    }
                }
                if (i == _SearchSteps + 1)
                {
                    nDistance = edgeStep * _Guess;
                }

                float edgeBlend = 0;
                if (pDistance > nDistance)
                {
                    if (sign(pLuminanceDelta) == sign(M - edgeLuminance))
                        edgeBlend = 0;
                    else
                        edgeBlend = 0.5f - pDistance / (pDistance + nDistance);
                }
                else
                {
                    if (sign(nLuminanceDelta) == sign(M - edgeLuminance))
                        edgeBlend = 0;
                    else
                        edgeBlend = 0.5f - nDistance / (pDistance + nDistance);
                }

                float finalBlend = max(pixelBlend, edgeBlend);
                
                return GetSource(uv + pixelStep * finalBlend);
            }
            

            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FXAAConsoleFragement

            // FXAA CONSOLE版本	
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _SourceSize;
            float _ContrastThreshold;
            float _RelativeThreshold;

            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }
            
            float4 FXAAConsoleFragement(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 TexelSize = _SourceSize.zw;
                float4 origin = GetSource(uv);
                float M = Luminance(origin);
                float NW = Luminance(GetSource(uv + float2(-TexelSize.x, TexelSize.y)));
                float NE = Luminance(GetSource(uv + float2(TexelSize.x, TexelSize.y)));
                float SW = Luminance(GetSource(uv + float2(-TexelSize.x, -TexelSize.y)));
                float SE = Luminance(GetSource(uv + float2(TexelSize.x, -TexelSize.y)));

                                //计算出对比度的值
                float maxLuma = max(max(max(NW,NE), max(SW, SE)), M);
                float minLuma = min(min(min(NW,NE), min(SW, SE)), M);
                float contrast = maxLuma - minLuma;

                //如果对比度值很小，认为不需要进行抗锯齿，直接跳过抗锯齿计算
                if (contrast < max(_ContrastThreshold, maxLuma * _RelativeThreshold))
                    return origin;

                NE += 1.0f / 384.0f;
                float2 dir = 0;
                dir.x = -((NW + NE) - (SW + SE));
                dir.y = ((NE + SE) - (NW + SE));
                dir = normalize(dir);

                const float _Scale = 0.5;
                float2 dir1 = dir * TexelSize * _Scale;

                float4 n1 = GetSource(uv - dir1);
                float4 p1 = GetSource(uv + dir1);
                float4 result = (n1 + p1) * 0.5f;

                const float _Sharpness = 8;
                float2 dirAbsMinTimesC = min(abs(dir1.x), abs(dir1.y)) * _Sharpness;
                float2 dir2 = clamp(dir1.xy / dirAbsMinTimesC, -2.0f, 2.0f) * 2.0;
                float4 n2 = GetSource(uv - dir2 * TexelSize);
                float4 p2 = GetSource(uv + dir2 * TexelSize);
                float4 result2 = result * 0.5f + (n2 + p2) * 0.25f;

                // 如果新的结果，亮度在正确范围内，则使用新的结果
                float newLuminance = Luminance(result2);
                if ((newLuminance >= minLuma) && (newLuminance <= maxLuma))
                    return result2;
                
                return result;
            }
            
            ENDHLSL
        }
    }
}
