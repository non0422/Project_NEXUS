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
        [Header(Specular)]
        _SpecInt ("高光强度", Range(0.0, 10.0)) = 0.5
        _SpecCol ("高光颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(PBR)]
        _Metallic ("金属度", Range(0.0, 1.0)) = 0.0
        _Roughness ("粗糙度", Range(0.0, 1.0)) = 0.5
        _FresnelInt ("菲涅尔", Range(0.0, 1.0)) = 0.5
        _F0 ("非金属反射率", Range(0.0, 0.16)) = 0.04
        [Header(EnvSpecular)]
        _EnvSpecInt ("环境高光强度", Range(0.0, 10.0)) = 1.0
        _EnvSpecCol ("环境高光颜色", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Emission)]
        _EmissionInt ("自发光强度", Range(0.0, 10.0)) = 1.0
        [HDR]_EmissionCol ("自发光颜色", Color) = (0.0, 0.0, 0.0, 0.0)      
        
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

            float4 _MainColor;
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
            //diffuse
                //half4 _LightColor;
            //Specular
            half _SpecInt;
            half4 _SpecCol;
            //PBR
            half _Metallic;
            half _Roughness;
            half _FresnelInt;
            half _F0;
            //EnvSpecular
            half _EnvSpecInt;
            half4 _EnvSpecCol;
            //Emission
            half _EmissionInt;
            half4 _EmissionCol;

            
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

                Light mainLight = GetMainLight();   //光照盒子
                half3 lightColor = mainLight.color; //光照颜色

                half3 lDirWS = normalize(mainLight.direction);
                half3 hDirWS = normalize(vDirWS + lDirWS);
                half3 rvDirWS = reflect(-vDirWS, nDirWS);
                
                //中间量准备
                half ndotl = saturate(dot(nDirWS, lDirWS)); // 法线与光照方向的夹角余弦值
                half ndotv = saturate(dot(nDirWS, vDirWS));// 法线与视线方向的夹角余弦值
                half ndoth = saturate(dot(nDirWS, hDirWS)); // 法线与半程向量的夹角余弦值
                half vdoth = saturate(dot(vDirWS, hDirWS)); // 视线方向与半程向量的夹角余弦值

                //采样
                half4 mainTexColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);   
                half aoTexColor = SAMPLE_TEXTURE2D(_AoTex, sampler_AoTex, i.uv).r;
                half metallicTexColor = SAMPLE_TEXTURE2D(_MetallicTex, sampler_MetallicTex, i.uv).r;
                half roughnessTexColor = SAMPLE_TEXTURE2D(_RoughnessTex, sampler_RoughnessTex, i.uv).r;
                half3 emissionTexColor = SAMPLE_TEXTURE2D(_EmissionTex, sampler_EmissionTex, i.uv).rgb;

                //光照计算
                half3 baseColor = mainTexColor.rgb * _MainColor.rgb;
                half metallic = saturate( metallicTexColor * _Metallic);
                half roughness = max(roughnessTexColor * _Roughness, 0.045); // 防止过于光滑的表面

                half3 diffCol = lerp(baseColor, half3(0.0, 0.0, 0.0), metallic);

                //漫反射光照
                half3 diffuse = diffCol * lightColor * ndotl;
                //镜面反射光照                
                half D = D_GGX9(ndoth, roughness);
                half G = G_Smith(ndotl, ndotv, roughness);

                half fresnel = pow(1.0 - vdoth, 5.0);
                half3 F0 = lerp(half3(_F0, _F0, _F0), baseColor, metallic);
                half3 F = saturate(F_Schlick(vdoth, F0) * _FresnelInt);

                half denominator = max(4.0 * ndotv * ndotl, 1e-5);
                half3 specularBRDF = D * G * F / denominator ; // 镜面反射光照计算
                
                half3 specular = specularBRDF * lightColor  * _SpecInt * _SpecCol.rgb; // 最终镜面反射光照

                //EnvDiffuse
                half3 envDiffuse = SampleSH(nDirWS);
                half3 envDif = envDiffuse * diffCol *aoTexColor;

                //EnvSpecular
                half specularAO = saturate(pow(ndotv + aoTexColor, exp2(-16.0 * roughness - 1.0))- 1.0 + aoTexColor);
                half3 envSpecCol = GlossyEnvironmentReflection(rvDirWS,roughness,1.0h);
                half3 envF = F0 + (1.0 - F0) * pow(1.0 - ndotv, 5.0);
                half3 envSpec = envSpecCol * envF * specularAO * _EnvSpecInt * _EnvSpecCol.rgb;

                //Emission
                half3 emission = emissionTexColor * _EmissionInt *_EmissionCol.rgb;

                //最终颜色计算
               return float4(diffuse + specular + envDif + envSpec + emission, 1.0);
              
            }

            ENDHLSL
        }
    }
}