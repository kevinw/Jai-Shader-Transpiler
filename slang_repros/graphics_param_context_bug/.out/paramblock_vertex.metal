#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
struct VSOut_0
{
    float4 pos_0;
};

struct VSIn_0
{
    uint vertex_id_0;
};

struct Params_default_0
{
    float2 device* positions_0;
};

struct KernelContext_0
{
    Params_default_0 constant* entryPointParams_params_0;
};

VSOut_0 VertexMain_0(const VSIn_0 thread* input_0, KernelContext_0 thread* kernelContext_0)
{
    thread VSOut_0 o_0;
    (&o_0)->pos_0 = float4(0.0) ;
    (&o_0)->pos_0 = float4(kernelContext_0->entryPointParams_params_0->positions_0[(*input_0).vertex_id_0], 0.0, 1.0);
    return o_0;
}

struct VertexMain_Result_0
{
    float4 pos_1 [[position]];
};

[[vertex]] VertexMain_Result_0 VertexMain(uint vertex_id_1 [[vertex_id]])
{
    thread VSIn_0 _S1;
    (&_S1)->vertex_id_0 = vertex_id_1;
    thread KernelContext_0 kernelContext_1;
    VSOut_0 _S2 = VertexMain_0(&_S1, &kernelContext_1);
    thread VertexMain_Result_0 _S3;
    (&_S3)->pos_1 = _S2.pos_0;
    return _S3;
}

