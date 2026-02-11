#version 450
layout(row_major) uniform;
layout(row_major) buffer;
layout(std430, binding = 0) buffer StructuredBuffer_uint_t_0 {
    uint _data[];
} values_0;
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main()
{
    uint _S1 = gl_GlobalInvocationID.x;
    if(_S1 < 64U)
    {
        values_0._data[uint(_S1)] = _S1;
    }
    return;
}

