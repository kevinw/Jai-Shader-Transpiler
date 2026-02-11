// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/array_shader_tests.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal>>)
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct _Array_std140_vector_float_2_3
{
    float4 data[3];
};

struct Array_Test_Vertex_Uniforms_std140
{
    _Array_std140_vector_float_2_3 u_offsets;
};

struct VertexMain_out
{
    float4 entryPointParam_VertexMain_gl_FragCoord [[user(locn0)]];
    float2 entryPointParam_VertexMain_sample_offset [[user(locn1)]];
    float4 gl_Position [[position]];
};

struct VertexMain_in
{
    float2 input_a_pos [[attribute(0)]];
};

vertex VertexMain_out VertexMain(VertexMain_in in [[stage_in]], constant Array_Test_Vertex_Uniforms_std140& un [[buffer(0)]])
{
    VertexMain_out out = {};
    out.gl_Position = float4(in.input_a_pos.x + 0.5, in.input_a_pos.y + un.u_offsets.data[2].y, 0.0, 1.0);
    out.entryPointParam_VertexMain_gl_FragCoord = float4(0.0);
    out.entryPointParam_VertexMain_sample_offset = float2(0.0, 0.5) + un.u_offsets.data[1].xy;
    return out;
}

