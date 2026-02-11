struct Vertex_Params
{
    StructuredBuffer<float2> positions;
    StructuredBuffer<float2> instances;
};

struct Pixel_Params
{
    StructuredBuffer<float> color;
};

struct VSIn
{
    uint vertex_id : SV_VertexID;
    uint instance_id : SV_InstanceID;
};

struct VSOut
{
    float4 pos : SV_Position;
};

struct FSIn
{
    float4 pos : SV_Position;
};

struct FSOut
{
    float4 out_color : SV_Target0;
};

[shader("vertex")]
VSOut VertexMain(VSIn input, Vertex_Params* vertex_data)
{
    VSOut o = (VSOut)0;
    float2 p = vertex_data->positions[input.vertex_id] + vertex_data->instances[input.instance_id];
    o.pos = float4(p, 0.0, 1.0);
    return o;
}

[shader("fragment")]
FSOut FragmentMain(FSIn input, Pixel_Params* fragment_data)
{
    FSOut o = (FSOut)0;
    o.out_color = float4(fragment_data->color[0], fragment_data->color[1], fragment_data->color[2], 1.0);
    return o;
}

