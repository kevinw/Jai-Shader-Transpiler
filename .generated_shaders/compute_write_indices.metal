#include <metal_stdlib>
using namespace metal;


kernel void ComputeMain(uint3 thread_id [[thread_position_in_grid]], device uint* values [[buffer(0)]]) {
     if (thread_id.x < 64) {
         values[thread_id.x] = thread_id.x;
     }
}

