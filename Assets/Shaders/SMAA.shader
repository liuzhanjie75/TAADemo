Shader "AA/SMAA"
{
    
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
                const float Threshold = 0.05f;
                float2 uv = i.texcoord;
                float2 size = _SourceSize.zw;
                float origin = Luminance(GetSource(uv));
                float L = abs(Luminance(GetSource(uv + float2(-size.x, 0))) - origin);
                float L2 = abs(Luminance(GetSource(uv + float2(-size.x * 2, 0))) - origin);
                float R = abs(Luminance(GetSource(uv + float2(size.x, 0))) - origin);
                float T = abs(Luminance(GetSource(uv + float2(0, -size.y))) - origin);
                float T2 = abs(Luminance(GetSource(uv + float2(0, -size.y * 2))) - origin);
                float B = abs(Luminance(GetSource(uv + float2(0, size.y))) - origin);

                float CMAX = max(max(L, R), max(T, B));
                // 判断左侧边界
                bool EL = (L > Threshold) && (max(CMAX, L2) * 0.5f);
                // 判断上侧边界
                bool ET = (T > Threshold) && (max(CMAX, T2) * 0.5f);
                
                return float4(EL ? 1 : 0, ET ? 1 : 0, 0, 0);
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

            // 圆角系数, 保留物体实际的边缘; 若为0 表示全保留, 为1表示不变
            #define ROUNDING_FACTOR 0.25
            // 最大搜索步长
            const int MAX_STEPS = 10;
            
            float4 _SourceSize;

            float4 GetSource(half2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, 0);
            }
            
            // 沿着左侧进行边界搜索
            float SearchXLeft(float2 coord)
            {
                coord -= float2(1.5f, 0);
                float e = 0;
                int i = 0;
                UNITY_LOOP
                for (; i < MAX_STEPS; ++i)
                {
                    e = GetSource(coord * _SourceSize.zw).g;
                    UNITY_FLATTEN
                    if (e < 0.9f)
                        break;
                    coord -= float2(2, 0);
                }
                return min(2.0 * (i + e), 2.0 * MAX_STEPS);
            }

            float SearchXRight(float2 coord)
            {
                coord += float2(1.5f, 0);
                float e = 0;
                int i = 0;
                UNITY_LOOP
                for (; i < MAX_STEPS; ++i)
                {
                    e = GetSource(coord * _SourceSize.zw).g;
                    UNITY_FLATTEN
                    if (e < 0.9f)
                        break;
                    coord += float2(2, 0);
                }
                return min(2.0 * (i + e), 2.0 * MAX_STEPS);
            }

            float SearchYUp(float2 coord)
            {
                coord -= float2(0, 1.5f);
                float e = 0;
                int i = 0;
                UNITY_LOOP
                for(; i < MAX_STEPS; i++)
                {
                    e = GetSource(coord * _SourceSize.zw).r;
                    UNITY_FLATTEN
                    if (e < 0.9f)
                        break;
                    coord -= float2(0, 2);
                }
                return min(2.0 * (i + e), 2.0 * MAX_STEPS);
            }

            float SearchYDown(float2 coord)
            {
                coord += float2(0, 1.5f);
                float e = 0;
                int i = 0;
                UNITY_LOOP
                for(; i < MAX_STEPS; i++)
                {
                    e = GetSource(coord * _SourceSize.zw).r;
                    UNITY_FLATTEN
                    if (e < 0.9f)
                        break;
                    coord += float2(0, 2);
                }
                return min(2.0 * (i + e), 2.0 * MAX_STEPS);
            }

            //这里是根据双线性采样得到的值，来判断边界的模式
            bool4 ModeOfSingle(float value)
            {
                bool4 ret = false;
                if (value > 0.875)
                    ret.yz = bool2(true, true);
                else if(value > 0.5)
                    ret.z = true;
                else if(value > 0.125)
                    ret.y = true;
                return ret;
            }
            
            //判断两侧的模式
            bool4 ModeOfDouble(float value1, float value2)
            {
                bool4 ret;
                ret.xy = ModeOfSingle(value1).yz;
                ret.zw = ModeOfSingle(value2).yz;
                return ret;
            }

            //  单侧L型, 另一侧没有, d表示总间隔, m表示像素中心距边缘距离
            //  |____
            // 
            float L_N_Shape(float d, float m)
            {
                float l = d * 0.5;
                float s = 0;
                [flatten]
                if ( l > (m + 0.5))
                {
                    // 梯形面积, 宽为1
                    s = (l - m) * 0.5 / l;
                }
                else if (l > (m - 0.5))
                {
                    // 三角形面积, a是宽, b是高
                    float a = l - m + 0.5;
                    // float b = a * 0.5 / l;
                    // float s = a * b * 0.5;
                    s = a * a * 0.25 * rcp(l);
                }
                return s;
            }

            //  双侧L型, 且方向相同
            //  |____|
            // 
            float L_L_S_Shape(float d1, float d2)
            {
                float d = d1 + d2;
                float s1 = L_N_Shape(d, d1);
                float s2 = L_N_Shape(d, d2);
                return s1 + s2;
            }

            //  双侧L型/或一侧L, 一侧T, 且方向不同, 这里假设左侧向上, 来取正负
            //  |____    |___|    
            //       |       |
            float L_L_D_Shape(float d1, float d2)
            {
                float d = d1 + d2;
                float s1 = L_N_Shape(d, d1);
                float s2 = -L_N_Shape(d, d2);
                return s1 + s2;
            }

            float Area(float2 d, bool4 left, bool4 right)
            {
                // result为正, 表示将该像素点颜色扩散至上/左侧; result为负, 表示将上/左侧颜色扩散至该像素
                float result = 0;
                UNITY_BRANCH
                if (!left.y && !left.z)
                {
                    UNITY_BRANCH
                    if (right.y && !right.z)
                        result = L_N_Shape(d.y + d.x + 1, d.y + 0.5);
                    else if (!right.y && right.z)
                        result = L_N_Shape(d.y + d.x + 1, d.y + 0.5);
                }
                else if (left.y && !left.z)
                {
                    UNITY_BRANCH
                    if(right.z)
                    {
                        result = L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                    }
                    else if (!right.y)
                    {
                        result = L_N_Shape(d.y + d.x + 1, d.x + 0.5);
                    }
                    else
                    {
                        result = L_L_S_Shape(d.x + 0.5, d.y + 0.5);
                    }
                }
                else if (!left.y && left.z)
                {
                    UNITY_BRANCH
                    if (right.y)
                    {
                        result = -L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                    }
                    else if (!right.z)
                    {
                        result = -L_N_Shape(d.x + d.y + 1, d.x + 0.5);
                    }
                    else
                    {
                        result = -L_L_S_Shape(d.x + 0.5, d.y + 0.5);
                    } 
                }
                else
                {
                    UNITY_BRANCH
                    if(right.y && !right.z)
                    {
                        result = -L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                    }
                    else if (!right.y && right.z)
                    {
                        result = L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                    }
                }

                #ifdef ROUNDING_FACTOR
                bool apply = false;
                if (result > 0)
                {
                    if(d.x < d.y && left.x)
                    {
                        apply = true;
                    }
                    else if(d.x >= d.y && right.x)
                    {
                        apply = true;
                    }
                }
                else if (result < 0)
                {
                    if(d.x < d.y && left.w)
                    {
                        apply = true;
                    }
                    else if(d.x >= d.y && right.w)
                    {
                        apply = true;
                    }
                }
                if (apply)
                {
                    result = result * ROUNDING_FACTOR;
                }
                #endif
                
                return result;
            }

            float4 FragBlend(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 screenPos = uv * _ScreenSize.xy;
                float2 edge = GetSource(uv).rg;
                float4 result = 0;
                
                if (edge.g > 0.1f)
                {
                    bool4 l, r;
                    float left = SearchXLeft(screenPos);
                    float right = SearchXRight(screenPos);
                    #ifdef ROUNDING_FACTOR
                    float left1 = GetSource((screenPos + float2(-left, -1.25)) * _ScreenSize.zw).r;
                    float left2 = GetSource((screenPos + float2(-left, 0.75)) * _ScreenSize.zw).r;
                    l = ModeOfDouble(left1, left2);
                    float right1 = GetSource((screenPos + float2(right + 1, -1.25)) * _ScreenSize.zw).r;
                    float right2 = GetSource((screenPos + float2(right + 1, 0.75)) * _ScreenSize.zw).r;
                    r = ModeOfDouble(right1, right2);
                    #else
                    float left3 = GetSource((screenPos + float2(-left, -0.25)) * _ScreenSize.zw).r;
                    float right3 = GetSource((screenPos + float2(right + 1, 0.75)) * _ScreenSize.zw).r;
                    l = ModeOfSingle(left3);
                    r = ModeOfSingle(right3);
                    #endif

                    float value = Area(float2(left, right), l, r);
                    result.xy = float2(-value, value);
                }

                if (edge.r > 0.1f)
                {
                    bool4 u, d;
                    float up = SearchYUp(screenPos);
                    float down = SearchYDown(screenPos);
                    #ifdef ROUNDING_FACTOR
                    float up1 = GetSource((screenPos + float2(-1.25, -up)) * _ScreenSize.zw).g;
                    float up2 = GetSource((screenPos + float2(0.75,  -up)) * _ScreenSize.zw).g;
                    u = ModeOfDouble(up1, up2);
                    float down1 = GetSource((screenPos + float2(-1.25, down + 1)) * _ScreenSize.zw).g;
                    float down2 = GetSource((screenPos + float2(0.75, down + 1)) * _ScreenSize.zw).g;
                    d = ModeOfDouble(down1, down2);
                    #else
                    float up3 = GetSource((screenPos + float2(-0.25, -up)) * _ScreenSize.zw).g;
                    float down3 = GetSource((screenPos + float2(0.75, down + 1)) * _ScreenSize.zw).g;
                    u = ModeOfSingle(up3);
                    d = ModeOfSingle(down3);
                    #endif

                    float value = Area(float2(up, down), u, d);
                    result.zw = float2(-value, value);
                }
                
                return float4(result);
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
                float2 uv = i.texcoord;
                int2 piexlCoord = uv * _SourceSize.xy;
                float4 TL = _BlendTex.Load(int3(piexlCoord, 0));
                float R = _BlendTex.Load(int3(piexlCoord + int2(1, 0), 0)).a;
                float B = _BlendTex.Load(int3(piexlCoord + int2(0, 1), 0)).g;

                float4 a = float4(TL.r, B, TL.b, R);
                float4 w = a * a * a;
                float sum = dot(w, 1.0);

                UNITY_BRANCH
                if (sum > 0)
                {
                    float4 o = a * _SourceSize.zzww;
                    float4 color = 0;
                    color = mad(GetSource(uv + float2(0, -o.r)), w.r, color);
                    color = mad(GetSource(uv + float2(0, o.g)), w.g, color);
                    color = mad(GetSource(uv + float2(-o.b, 0)), w.b, color);
                    color = mad(GetSource(uv + float2(o.a, 0)), w.a, color);
                    return color / sum;
                }
                else
                {
                    return GetSource(uv);
                }
            }
            
            ENDHLSL
        }
    }
}
