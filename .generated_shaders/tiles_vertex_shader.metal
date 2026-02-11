// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/glsl_shaders.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal>>)
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct VertexMain_out
{
    float4 entryPointParam_VertexMain_gl_FragCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct VertexMain_in
{
    float2 input_a_pos [[attribute(0)]];
};

vertex VertexMain_out VertexMain(VertexMain_in in [[stage_in]])
{
    VertexMain_out out = {};
    out.gl_Position = float4(in.input_a_pos, 0.0, 1.0);
    out.entryPointParam_VertexMain_gl_FragCoord = float4(0.0);
    return out;
}

