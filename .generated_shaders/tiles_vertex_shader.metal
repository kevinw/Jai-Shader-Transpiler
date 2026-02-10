#include <metal_stdlib>
using namespace metal;

struct VertexShader_In {
    float2 a_pos [[attribute(0)]];
};

struct VertexShader_Uniforms {
};

struct VertexShader_Out {
    float4 gl_Position [[position]];
    float4 gl_FragCoord [[user(gl_FragCoord)]];
};


vertex VertexShader_Out VertexMain(VertexShader_In in [[stage_in]], constant VertexShader_Uniforms& un [[buffer(0)]]) {
     float2 a_pos = in.a_pos;
     float4 gl_Position;

     gl_Position = float4(a_pos.x, a_pos.y, 0.0, 1);
     VertexShader_Out out;
     out.gl_Position = gl_Position;
     out.gl_FragCoord = gl_Position;
     return out;
}

