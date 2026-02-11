// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/compute_shader_tests.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal>>)
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct _6
{
    uint _m0[1];
};

kernel void ComputeMain(device _6& values [[buffer(0)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    if (gl_GlobalInvocationID.x < 64u)
    {
        values._m0[gl_GlobalInvocationID.x] = gl_GlobalInvocationID.x;
    }
}

