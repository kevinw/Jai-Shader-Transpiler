#include <metal_stdlib>
using namespace metal;

struct Array_Test_Vertex_In {
    float2 a_pos [[attribute(0)]];
};

struct Array_Test_Vertex_Uniforms {
    float2 u_offsets[3];
};

struct Array_Test_Vertex_Out {
    float4 gl_Position [[position]];
    float2 sample_offset [[user(sample_offset)]];
};


vertex Array_Test_Vertex_Out VertexMain(Array_Test_Vertex_In in [[stage_in]], constant Array_Test_Vertex_Uniforms& un [[buffer(0)]]) {
     float2 a_pos = in.a_pos;
     float2 u_offsets[3];
     u_offsets[0] = un.u_offsets[0];
     u_offsets[1] = un.u_offsets[1];
     u_offsets[2] = un.u_offsets[2];
     float4 gl_Position;
     float2 sample_offset;

     float2 positions[3] = {float2(0.0, 0.5), float2(-0.5, -0.5), float2(0.5, -0.5)};
     sample_offset = positions[0] + u_offsets[1];
     gl_Position = float4(a_pos.x + positions[2].x, a_pos.y + u_offsets[2].y, 0.0, 1);
     Array_Test_Vertex_Out out;
     out.gl_Position = gl_Position;
     out.sample_offset = sample_offset;
     return out;
}

