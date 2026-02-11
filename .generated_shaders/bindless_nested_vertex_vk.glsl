#version 450 core
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

layout(buffer_reference, std430) readonly buffer Ptr_BindlessNestedVk_VertexData {
    vec2 offset;
};

layout(buffer_reference, std430) readonly buffer BindlessNestedVk_Params {
    Ptr_BindlessNestedVk_VertexData vertex_data;
};

layout(push_constant) uniform PushConstants {
    uint64_t params_addr;
} push_constants;

layout (location=0) in vec2 a_pos;



void main() {
     BindlessNestedVk_Params params = BindlessNestedVk_Params(push_constants.params_addr);
     vec2 p = params.vertex_data.offset + a_pos;
     gl_Position = vec4(p.x, p.y, 0.0, 1);
}

