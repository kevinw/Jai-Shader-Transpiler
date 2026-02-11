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
    uint instance_id_0;
};

struct KernelContext_0
{
    float2 device* device* entryPointParams_vertex_data_positions_0;
    float2 device* device* entryPointParams_vertex_data_instances_0;
    float device* device* entryPointParams_fragment_data_color_0;
};

VSOut_0 VertexMain_0(const VSIn_0 thread* input_0, KernelContext_0 thread* kernelContext_0)
{
    thread VSOut_0 o_0;
    (&o_0)->pos_0 = float4(0.0) ;
    (&o_0)->pos_0 = float4((*kernelContext_0->entryPointParams_vertex_data_positions_0)[(*input_0).vertex_id_0] + (*kernelContext_0->entryPointParams_vertex_data_instances_0)[(*input_0).instance_id_0], 0.0, 1.0);
    return o_0;
}

struct FSOut_0
{
    float4 out_color_0 [[color(0)]];
};

[[fragment]] FSOut_0 FragmentMain(float4 pos_1 [[position]], float device* device* entryPointParams_fragment_data_color_1)
{
    thread FSOut_0 o_1;
    (&o_1)->out_color_0 = float4(0.0) ;
    (&o_1)->out_color_0 = float4((*entryPointParams_fragment_data_color_1)[int(0)], (*entryPointParams_fragment_data_color_1)[int(1)], (*entryPointParams_fragment_data_color_1)[int(2)], 1.0);
    return o_1;
}

struct VertexMain_Result_0
{
    float4 pos_2 [[position]];
};

[[vertex]] VertexMain_Result_0 VertexMain(uint vertex_id_1 [[vertex_id]], uint instance_id_1 [[instance_id]])
{
    thread VSIn_0 _S1;
    (&_S1)->vertex_id_0 = vertex_id_1;
    (&_S1)->instance_id_0 = instance_id_1;
    thread KernelContext_0 kernelContext_1;
    VSOut_0 _S2 = VertexMain_0(&_S1, &kernelContext_1);
    thread VertexMain_Result_0 _S3;
    (&_S3)->pos_2 = _S2.pos_0;
    return _S3;
}

