#version 450

struct BindlessNestedVk_VertexData_std430_logical
{
    vec2 offset;
};

struct BindlessNestedVk_VertexData_std430
{
    vec2 offset;
};

layout(set = 0, binding = 0, std430) readonly buffer StructuredBuffer
{
    BindlessNestedVk_VertexData_std430 _m0[];
} params_vertex_data;

layout(location = 0) in vec2 input_a_pos;

void main()
{
    BindlessNestedVk_VertexData_std430_logical _31;
    _31.offset = params_vertex_data._m0[0].offset;
    gl_Position = vec4(_31.offset + input_a_pos, 0.0, 1.0);
}

