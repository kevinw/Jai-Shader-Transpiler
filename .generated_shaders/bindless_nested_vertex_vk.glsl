#version 450
layout(row_major) uniform;
layout(row_major) buffer;
struct BindlessNestedVk_VertexData_0
{
    vec2 offset_0;
};

layout(std430, binding = 0) readonly buffer StructuredBuffer_BindlessNestedVk_VertexData_t_0 {
    BindlessNestedVk_VertexData_0 _data[];
} params_vertex_data_0;
layout(location = 0)
in vec2 input_a_pos_0;

struct bindless_nested_vertex_vk_Out_0
{
    vec4 Ugl_Position_0;
};

void main()
{
    bindless_nested_vertex_vk_Out_0 o_0;
    o_0.Ugl_Position_0 = vec4(0.0);
    vec2 p_0 = params_vertex_data_0._data[uint(0)].offset_0 + input_a_pos_0;
    o_0.Ugl_Position_0 = vec4(p_0.x, p_0.y, 0.0, 1.0);
    gl_Position = o_0.Ugl_Position_0;
    return;
}

