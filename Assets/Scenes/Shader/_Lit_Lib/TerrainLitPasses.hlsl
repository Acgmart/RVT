
#ifdef UNITY_INSTANCING_ENABLED
    TEXTURE2D(_TerrainHeightmapTexture);
#endif

#ifdef _RVT
    float4 _VTFeedbackParam;
    float4 _VTPageParam;
    float4 _VTTileParam;
    float4 _VTRealRect;
    sampler2D _VTLookupTex;
    sampler2D _VTDiffuse;
#endif

UNITY_INSTANCING_BUFFER_START(Terrain)
    UNITY_DEFINE_INSTANCED_PROP(float4, _TerrainPatchInstanceData)  // float4(xBase, yBase, skipScale, ~)
UNITY_INSTANCING_BUFFER_END(Terrain)

struct a2v
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float4 uv0              : TEXCOORD0; // xy: control, zw: lightmap
    float4 uvSplat01                : TEXCOORD1; // xy: splat0, zw: splat1
    float4 uvSplat23                : TEXCOORD2; // xy: splat2, zw: splat3
    float3 positionWS               : TEXCOORD7;
    float4 clipPos                  : SV_POSITION;
};

void SplatmapMix(float4 uvSplat01, float4 uvSplat23, inout half4 splatControl, out half4 mixedDiffuse)
{
    half4 diffAlbedo[4];
    diffAlbedo[0] = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, uvSplat01.xy);
    diffAlbedo[1] = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat0, uvSplat01.zw);
    diffAlbedo[2] = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat0, uvSplat23.xy);
    diffAlbedo[3] = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat0, uvSplat23.zw);
    mixedDiffuse = 0.0h;
    mixedDiffuse += diffAlbedo[0] * splatControl.r;
    mixedDiffuse += diffAlbedo[1] * splatControl.g;
    mixedDiffuse += diffAlbedo[2] * splatControl.b;
    mixedDiffuse += diffAlbedo[3] * splatControl.a;
}

void TerrainInstancing(inout float4 positionOS, inout float2 uv)
{
#ifdef UNITY_INSTANCING_ENABLED
    float2 patchVertex = positionOS.xy;
    float4 instanceData = UNITY_ACCESS_INSTANCED_PROP(Terrain, _TerrainPatchInstanceData);
    float2 sampleCoords = (patchVertex.xy + instanceData.xy) * instanceData.z; // (xy + float2(xBase,yBase)) * skipScale
    float height = UnpackHeightmap(_TerrainHeightmapTexture.Load(int3(sampleCoords, 0)));
    positionOS.xz = sampleCoords * _TerrainHeightmapScale.xz;
    positionOS.y = height * _TerrainHeightmapScale.y;
    uv = sampleCoords * _TerrainHeightmapRecipSize.zw;
#endif
}

v2f vert(a2v i)
{
    v2f o = (v2f)0;
    UNITY_SETUP_INSTANCE_ID(i);
    TerrainInstancing(i.positionOS, i.texcoord);
    VertexPositionInputs Attributes = GetVertexPositionInputs(i.positionOS.xyz);
    o.uv0.xy = i.texcoord;
    o.uvSplat01.xy = TRANSFORM_TEX(i.texcoord, _Splat0);
    o.uvSplat01.zw = TRANSFORM_TEX(i.texcoord, _Splat1);
    o.uvSplat23.xy = TRANSFORM_TEX(i.texcoord, _Splat2);
    o.uvSplat23.zw = TRANSFORM_TEX(i.texcoord, _Splat3);
    o.positionWS = Attributes.positionWS;
    o.clipPos = Attributes.positionCS;
    return o;
}

#ifdef _RVT
half4 GetRVTColor(v2f i)
{
    float2 uv = (i.positionWS.xz - _VTRealRect.xy) / _VTRealRect.zw;
    float2 uvInt = uv - frac(uv * _VTPageParam.x) * _VTPageParam.y;
	float4 page = tex2D(_VTLookupTex, uvInt) * 255;
    #ifdef _SHOWRVTMIPMAP
        return float4(clamp(1 - page.b * 0.1 , 0, 1), 0, 0, 1);
    #endif
	float2 inPageOffset = frac(uv * exp2(_VTPageParam.z - page.b));
    uv = (page.rg * (_VTTileParam.y + _VTTileParam.x * 2) + inPageOffset * _VTTileParam.y + _VTTileParam.x) / _VTTileParam.zw;
    half3 albedo = tex2D(_VTDiffuse, uv);
    return half4(albedo, 1.0);
}
#endif

half4 frag(v2f i) : SV_TARGET
{
    #ifdef _RVT
        return GetRVTColor(i);
    #endif

    float2 splatUV = (i.uv0.xy * (_Control_TexelSize.zw - 1.0f) + 0.5f) * _Control_TexelSize.xy;
    half4 splatControl = SAMPLE_TEXTURE2D(_Control, sampler_Control, splatUV);
    half4 mixedDiffuse;
    SplatmapMix(i.uvSplat01, i.uvSplat23, splatControl, mixedDiffuse);
    half3 albedo = mixedDiffuse.rgb;
    return half4(albedo, 1.0h);
}
