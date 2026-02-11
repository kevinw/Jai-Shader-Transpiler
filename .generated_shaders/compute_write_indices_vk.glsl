#version 450
layout(row_major) uniform;
layout(row_major) buffer;

#line 9 0
layout(std430, binding = 0) buffer StructuredBuffer_uint_t_0 {
    uint _data[];
} entryPointParams_values_0;

#line 9
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main()
{

#line 10
    uint _S1 = gl_GlobalInvocationID.x;

#line 10
    if(_S1 < 64U)
    {

#line 11
        entryPointParams_values_0._data[uint(_S1)] = _S1;

#line 10
    }


    return;
}

