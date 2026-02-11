// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/vulkan_shaders.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL>>)
#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer values
{
    uint _m0[];
} values_1;

void main()
{
    if (gl_GlobalInvocationID.x < 64u)
    {
        values_1._m0[gl_GlobalInvocationID.x] = gl_GlobalInvocationID.x;
    }
}

