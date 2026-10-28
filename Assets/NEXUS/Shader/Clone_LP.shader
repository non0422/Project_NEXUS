Shader "NEXUS/Shader/Clone_LP"
{
    Properties
    {
        _MainColor ("颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Texture)]
        _MainTex ("纹理", 2D) = "white" {}
        _NormalTex ("法线贴图", 2D) = "bump" {}
        _AoTex ("环境光遮蔽贴图", 2D) = "white" {}
        _MetallicTex ("金属度贴图", 2D) = "white" {}
        _RoughnessTex ("粗糙度贴图", 2D) = "black" {}
        _EmissionTex ("自发光贴图", 2D) = "black" {}
        [Header(Fresnel)]
        _FresnelInt ("菲涅尔强度", Range(0.0, 10.0)) = 0.5
        _FresnelPower("边缘光范围", Range(1, 30)) = 10
        _FresnelCol ("菲涅尔颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Diffuse)]
        _DiffuseInt ("漫反射强度", Range(0.0, 10.0)) = 1.0
        _DiffuseCol ("漫反射颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Specular)]
        _SpecInt ("高光强度", Range(0.0, 100.0)) = 0.5
        _SpecCol ("高光颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(PBR)]
        _Metallic ("金属度", Range(0.0, 1.0)) = 0.0
        _MinRoughness ("min粗糙度", Range(0.045, 1.0)) = 0.1
        _MaxRoughness ("max粗糙度", Range(0.045, 1.0)) = 0.6
        
        _F0 ("非金属反射率", Range(0.0, 0.16)) = 0.04
        [Header(EnvDiffuse)]
        _EnvDifInt ("环境漫反射强度", Range(0.0, 30.0)) = 1.0
        [Header(EnvSpecular)]
        _EnvSpecInt ("环境高光强度", Range(0.0, 10.0)) = 1.0
        _EnvSpecCol ("环境高光颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Emission)]
        _EmissionInt ("自发光强度", Range(0.0, 10.0)) = 1.0
        [HDR]_EmissionCol ("自发光颜色", Color) = (0.0, 0.0, 0.0, 0.0)
        [Header(PlanarShadow)]  
        _PlanarShadowOpacity ("平面阴影透明度", Range(0.0, 1.0)) = 0.5 
        _ShadowStrength("自阴影强度", Range(0, 2.0)) = 1.0
    }

    SubShader
    {
        Tags { 
            "RenderType"="Opaque" 
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Tags { "LightMode" ="UniversalForward" }
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
                        
            //纹理资源
            TEXTURE2D(_MainTex);
            TEXTURE2D(_NormalTex);
            TEXTURE2D(_AoTex);
            TEXTURE2D(_MetallicTex);
            TEXTURE2D(_RoughnessTex);
            TEXTURE2D(_EmissionTex);
            //采样器
            SAMPLER(sampler_MainTex);
            SAMPLER(sampler_NormalTex);
            SAMPLER(sampler_AoTex);
            SAMPLER(sampler_MetallicTex);
            SAMPLER(sampler_RoughnessTex);
            SAMPLER(sampler_EmissionTex);

            CBUFFER_START(UnityPerMaterial)
            float4 _MainColor;
            //Fresnel
            half _FresnelInt;
            half _FresnelPower;
            half4 _FresnelCol;
            //diffuse
            half _DiffuseInt;
            half4 _DiffuseCol;
            //Specular
            half _SpecInt;
            half4 _SpecCol;
            //PBR
            half _Metallic;
            half _MinRoughness;
            half _MaxRoughness;
            half _F0;
            //EnvDiffuse
            half _EnvDifInt;
            //EnvSpecular
            half _EnvSpecInt;
            half4 _EnvSpecCol;
            //Emission
            half _EmissionInt;
            half4 _EmissionCol;
            //Shadow
            half _ShadowStrength;
            CBUFFER_END
           

            struct a2v
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float3 nDirWS : TEXCOORD2;
                float3 tDirWS : TEXCOORD3;
                float3 bDirWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
            };

            half D_GGX9(half ndoth, half roughness)
            {
                half alpha = roughness * roughness;
                half alpha2 = alpha * alpha;
                half denom = ndoth * ndoth * (alpha2 - 1.0) + 1.0;
                return alpha2 /max(PI * denom * denom, 1e-5);
            }

            half G_SchlickGGX(half NdotX, half roughness)
            {
                half r = roughness + 1.0;
                half k = r * r / 8.0;

                return NdotX /
                    max(NdotX * (1.0 - k) + k, 0.0001);
            }

            half G_Smith(half NdotL, half NdotV, half roughness)
            {
                half G_L = G_SchlickGGX(NdotL, roughness);
                half G_V = G_SchlickGGX(NdotV, roughness);

                return G_L * G_V;
            }

            half3 F_Schlick(half VdotH, half3 F0)
            {
                half fresnel = pow(1.0 - VdotH, 5.0);
                return F0 + (1.0 - F0) * fresnel;
            }

            v2f vert(a2v v)
            {
                v2f o;
                o.pos = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.posWS = TransformObjectToWorld(v.vertex).xyz;

                o.nDirWS = TransformObjectToWorldNormal(v.normal);
                o.tDirWS = TransformObjectToWorldDir(v.tangent.xyz);
                o.bDirWS = cross(o.nDirWS, o.tDirWS) * v.tangent.w;
                o.shadowCoord = TransformWorldToShadowCoord(o.posWS);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                //向量准备
                half3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, i.uv));
                half3 tDirWS = normalize(i.tDirWS);
                half3 bDirWS = normalize(i.bDirWS);
                half3 normalWS = normalize(i.nDirWS);

                half3 nDirWS = normalize( tDirWS * nDirTS.x + bDirWS * nDirTS.y + normalWS * nDirTS.z);
                half3 vDirWS = normalize(_WorldSpaceCameraPos - i.posWS);

                
                Light mainLight = GetMainLight(i.shadowCoord);   //光照盒子
                half shadowAttenuation = lerp(1.0h,mainLight.shadowAttenuation,_ShadowStrength); //阴影衰减系数
                half3 lightColor = mainLight.color * shadowAttenuation;

                half3 lDirWS = normalize(mainLight.direction);
                half3 hDirWS = normalize(vDirWS + lDirWS);
                half3 rvDirWS = reflect(-vDirWS, nDirWS);
                
                //中间量准备
                half ndotl = saturate(dot(nDirWS, lDirWS)); // 法线与光照方向的夹角余弦值
                half ndotv = saturate(dot(nDirWS, vDirWS));// 法线与视线方向的夹角余弦值
                half ndoth = saturate(dot(nDirWS, hDirWS)); // 法线与半程向量的夹角余弦值
                half vdoth = saturate(dot(vDirWS, hDirWS)); // 视线方向与半程向量的夹角余弦值

                //采样
                half3 mainTexColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;   
                half aoTexColor = SAMPLE_TEXTURE2D(_AoTex, sampler_AoTex, i.uv).r;
                half metallicTexColor = SAMPLE_TEXTURE2D(_MetallicTex, sampler_MetallicTex, i.uv).r;
                half roughnessTexColor = SAMPLE_TEXTURE2D(_RoughnessTex, sampler_RoughnessTex, i.uv).r;
                half3 emissionTexColor = SAMPLE_TEXTURE2D(_EmissionTex, sampler_EmissionTex, i.uv).rgb;

                // Fresnel 边缘光
                half fresnel = pow(1.0h - ndotv, _FresnelPower);
                half3 fresnelColor = fresnel * _FresnelInt * _FresnelCol.rgb;
                
                //光照计算
                half3 baseColor = mainTexColor.rgb * _MainColor.rgb;
                half metallic = saturate( metallicTexColor * _Metallic);
                half roughness = lerp(_MinRoughness, _MaxRoughness, roughnessTexColor);

                half3 diffCol = lerp(baseColor, half3(0.0, 0.0, 0.0),metallic);
                diffCol *= _DiffuseCol.rgb;

                //漫反射光照
                half3 diffuse = diffCol * lightColor * ndotl  * _DiffuseInt;
                //镜面反射光照                
                half D = D_GGX9(ndoth, roughness);
                half G = G_Smith(ndotl, ndotv, roughness);

                half3 F0 = lerp(half3(_F0, _F0, _F0), baseColor, metallic);
                half3 F = F_Schlick(vdoth, F0);

                half denominator = max(4.0 * ndotv * ndotl, 1e-5);
                half3 specularBRDF = D * G * F / denominator ; // 镜面反射光照计算
                
                half3 specular = specularBRDF * lightColor *ndotl * _SpecInt * _SpecCol.rgb; // 最终镜面反射光照

                //EnvDiffuse
                half3 envDif = SampleSH(nDirWS);
                half3 envDiffuse = envDif * diffCol *aoTexColor * _EnvDifInt;

                //EnvSpecular
                half specularAO = saturate(pow(ndotv + aoTexColor, exp2(-16.0 * roughness - 1.0))- 1.0 + aoTexColor);
                half3 envSpecCol = GlossyEnvironmentReflection(rvDirWS,roughness,1.0h);
                half3 envF = F0 + (1.0 - F0) * pow(1.0 - ndotv, 5.0);
                half3 envSpec = envSpecCol * envF * specularAO * _EnvSpecInt * _EnvSpecCol.rgb;

                //Emission
                half3 emission = emissionTexColor * _EmissionInt *_EmissionCol.rgb;

                //最终颜色计算
                half3 finalColor = diffuse + specular + envDiffuse + envSpec + emission + fresnelColor;
                return float4(finalColor, 1.0);
                
            }

            ENDHLSL   
         
        } 
       
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        // Pass
        // {
        //     Name "PlanarShadow"
        //     Tags { "LightMode" = "SRPDefaultUnlit" }

        //     ZWrite Off
        //     ZTest LEqual
        //     Blend SrcAlpha OneMinusSrcAlpha
        //     Cull Off

        //     HLSLPROGRAM
        //     #pragma vertex vert
        //     #pragma fragment frag

        //     #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        //     #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        //     #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        //     half _PlanarShadowOpacity;

        //     struct Attributes
        //     {
        //         float4 positionOS : POSITION;
        //     };

        //     struct Varyings
        //     {
        //         float4 positionCS : SV_POSITION;
        //     };

        //     Varyings vert(Attributes v)
        //     {
        //         Varyings o;

        //         // 模型顶点转换到世界空间
        //         float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);

        //         // 获取主光源方向
        //         float3 lightDirWS = normalize(GetMainLight().direction);

        //         // 地面高度
        //         float groundY = 0.01;

        //         // 仅支持从上方照射的主光源
        //         float denominator = -lightDirWS.y;

        //         // 沿光线反方向求与地面的交点
        //         float safeDenominator = max(denominator, 0.15);

        //         float distanceToGround =
        //             (positionWS.y - groundY) / safeDenominator;

        //         float3 shadowWS =
        //             positionWS - lightDirWS * distanceToGround;

        //         // 固定在地面平面
        //         shadowWS.y = groundY;

        //         o.positionCS = TransformWorldToHClip(shadowWS);
        //         return o;
        //     }

        //     half4 frag(Varyings i) : SV_Target
        //     {
        //         return half4(0.0, 0.0, 0.0, _PlanarShadowOpacity);
        //     }
        //     ENDHLSL
        // }
    }
    
}