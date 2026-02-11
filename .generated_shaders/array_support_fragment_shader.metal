// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/array_shader_tests.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal>>)
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct _Array_std140_vector_float_4_2
{
    float4 data[2];
};

struct Array_Test_Fragment_Uniforms_std140
{
    _Array_std140_vector_float_4_2 u_palette;
};

struct FragmentMain_out
{
    float4 entryPointParam_FragmentMain_out_color [[color(0)]];
};

struct FragmentMain_in
{
    float2 input_sample_offset [[user(locn0)]];
};

fragment FragmentMain_out FragmentMain(FragmentMain_in in [[stage_in]], constant Array_Test_Fragment_Uniforms_std140& un [[buffer(0)]])
{
    FragmentMain_out out = {};
    out.entryPointParam_FragmentMain_out_color = (float4(1.0, 0.0, 0.0, 1.0) * (in.input_sample_offset.x + 0.5)) + (un.u_palette.data[1] * 0.5);
    return out;
}

