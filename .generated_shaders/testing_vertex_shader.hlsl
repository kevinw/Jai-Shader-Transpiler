struct VertexShader_In {
    float2 a_pos : A_POS;
}
cbuffer VertexShader_CBuffer {
    float2 test;
}
Texture2D texture : register(t0);
SamplerState sampler : register(s0);
struct VertexShader_Out {
}

VertexShader_Out main(VertexShader_In in) {
     VertexShader_Out out;
     out.f_pos=in.a_pos;
}

