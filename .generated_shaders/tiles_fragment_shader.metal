// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/glsl_shaders.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal>>)
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Implementation of the GLSL radians() function
template<typename T>
inline T radians(T d)
{
    return d * T(0.01745329251);
}

struct FragmentShader_Uniforms_std140
{
    float2 u_resolution;
    float u_time;
};

struct FragmentMain_out
{
    float4 entryPointParam_FragmentMain_out_color [[color(0)]];
};

fragment FragmentMain_out FragmentMain(constant FragmentShader_Uniforms_std140& un [[buffer(0)]], float4 gl_FragCoord [[position]])
{
    FragmentMain_out out = {};
    float _45 = radians((-30.0) - un.u_time);
    float _47 = cos(_45);
    float _48 = sin(_45);
    float2 scaled_uv = (float2x2(float2(_47, _48), float2(-_48, _47)) * ((gl_FragCoord.xy / float2(un.u_resolution.x)) - float2(0.5, 0.5 * (un.u_resolution.y / un.u_resolution.x)))) * 20.0;
    float2 _57 = fract(scaled_uv);
    float _58 = _57.x;
    float _62 = _57.y;
    float _65 = fast::min(fast::min(_58, 1.0 - _58), fast::min(_62, 1.0 - _62));
    float _67 = length(floor(scaled_uv));
    float _71 = sin(un.u_time - (_67 * 20.0));
    float _74 = fmod(_71 * _71, _71 / _71);
    float edge = powr(abs(1.0 - _74), 2.2000000476837158203125) * 0.5;
    float value = (smoothstep(edge - 0.0500000007450580596923828125, edge, 0.949999988079071044921875 * mix(_65, 1.0 - _65, step(1.0, _74))) + (_67 * 0.100000001490116119384765625)) * 0.60000002384185791015625;
    out.entryPointParam_FragmentMain_out_color = float4(powr(value, 2.0), powr(value, 1.5), powr(value, 1.2000000476837158203125), 1.0);
    return out;
}

