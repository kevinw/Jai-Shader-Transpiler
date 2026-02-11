struct Params
{
    StructuredBuffer<float2> positions;
};

struct VSIn
{
    uint vertex_id : SV_VertexID;
};

struct VSOut
{
    float4 pos : SV_Position;
};

[shader("vertex")]
VSOut VertexMain(VSIn input, ParameterBlock<Params> params)
{
    VSOut o = (VSOut)0;
    float2 p = params.positions[input.vertex_id];
    o.pos = float4(p, 0.0, 1.0);
    return o;
}

