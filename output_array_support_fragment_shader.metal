#include <metal_stdlib>
using namespace metal;

struct Array_Test_Vertex_Out {
    float4 gl_FragCoord [[position]];
    float2 sample_offset [[user(sample_offset)]];
};

struct Array_Test_Fragment_Uniforms {
    float4 u_palette[2];
};

struct Array_Test_Fragment_Out {
    float4 out_color [[color(0)]];
};


fragment Array_Test_Fragment_Out FragmentMain(Array_Test_Vertex_Out in [[stage_in]], constant Array_Test_Fragment_Uniforms& un [[buffer(0)]]) {
     float4 gl_FragCoord = in.gl_FragCoord;
     float2 sample_offset = in.sample_offset;
     float4 u_palette[2];
     u_palette[0] = un.u_palette[0];
     u_palette[1] = un.u_palette[1];
     float4 out_color;

     float4 local_palette[2] = {float4(1, 0.0, 0.0, 1), float4(0.0, 1, 0.0, 1)};
     out_color = local_palette[0] * sample_offset.x + 0.5 + u_palette[1] * 0.5;
     Array_Test_Fragment_Out out;
     out.out_color = out_color;
     return out;
}

