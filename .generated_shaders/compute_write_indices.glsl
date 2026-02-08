#version 430 core
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(std430, binding = 0) buffer values_Buffer {
    uint values[];
};


void main() {
     uvec3 thread_id = gl_GlobalInvocationID;
     if (thread_id.x < 64) {
         values[thread_id.x] = thread_id.x;
     }
}

