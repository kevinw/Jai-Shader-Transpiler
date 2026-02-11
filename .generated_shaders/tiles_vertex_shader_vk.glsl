// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/vulkan_shaders.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL>>)
#version 450

layout(location = 0) in vec2 input_a_pos;
layout(location = 0) out vec4 entryPointParam_VertexMain_gl_FragCoord;

void main()
{
    gl_Position = vec4(input_a_pos, 0.0, 1.0);
    entryPointParam_VertexMain_gl_FragCoord = vec4(0.0);
}

