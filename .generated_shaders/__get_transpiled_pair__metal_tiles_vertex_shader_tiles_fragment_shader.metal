#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1204 "core.meta.slang"
float float_getPi_0()
{

#line 1204
    return 3.14159274101257324;
}


#line 13319 "hlsl.meta.slang"
float radians_0(float x_0)
{

#line 13330
    return x_0 * (float_getPi_0() / 180.0);
}


#line 19 ".build/ir_slang/__get_transpiled_pair__metal_tiles_vertex_shader_tiles_fragment_shader_pair.slang"
struct tiles_fragment_shader_Out_0
{
    float4 out_color_0 [[user(OUT_COLOR)]];
};


#line 19
struct pixelInput_0
{
    float4 gl_Position_0 [[user(GL_POSITION)]];
    float4 gl_FragCoord_0 [[user(GL_FRAGCOORD)]];
    float2 u_resolution_0 [[user(U_RESOLUTION)]];
    float u_time_0 [[user(U_TIME)]];
};


#line 39
[[fragment]] tiles_fragment_shader_Out_0 FragmentMain(pixelInput_0 _S1 [[stage_in]])
{

#line 40
    thread tiles_fragment_shader_Out_0 o_0;

#line 40
    (&o_0)->out_color_0 = float4(0.0) ;
    float _S2 = _S1.u_resolution_0.x;


    float rot_0 = radians_0(-30.0 - _S1.u_time_0);
    float _S3 = cos(rot_0);

#line 45
    float _S4 = sin(rot_0);

    float2 scaled_uv_0 = float2(20.0)  * (((matrix<float,int(2),int(2)> (float2(_S3, _S4), float2(- _S4, _S3))) * (_S1.gl_FragCoord_0.xy / float2(_S2)  - float2(0.5, 0.5 * (_S1.u_resolution_0.y / _S2)))));
    float2 _S5 = fract(scaled_uv_0);
    float _S6 = _S5.x;

#line 49
    float _S7 = _S5.y;

#line 49
    float tile_dist_0 = min(min(_S6, 1.0 - _S6), min(_S7, 1.0 - _S7));
    float square_dist_0 = length(floor(scaled_uv_0));
    float edge_0 = sin(_S1.u_time_0 - square_dist_0 * 20.0);
    float _S8 = edge_0 * edge_0;

#line 52
    float _S9 = edge_0 / edge_0;

#line 52
    float edge_1 = ((((_S8) < 0.0) ? -fmod(-(_S8),abs((_S9))) : fmod((_S8),abs((_S9)))));

    float edge_2 = pow(abs(1.0 - edge_1), 2.20000004768371582) * 0.5;


    float value_0 = (smoothstep(edge_2 - 0.05000000074505806, edge_2, 0.94999998807907104 * mix(tile_dist_0, 1.0 - tile_dist_0, step(1.0, edge_1))) + square_dist_0 * 0.10000000149011612) * 0.60000002384185791;
    (&o_0)->out_color_0 = float4(pow(value_0, 2.0), pow(value_0, 1.5), pow(value_0, 1.20000004768371582), 1.0);
    return o_0;
}


#line 59
struct VertexMain_Result_0
{
    float4 gl_Position_1 [[user(GL_POSITION)]];
    float4 gl_FragCoord_1 [[user(GL_FRAGCOORD)]];
};


#line 59
struct vertexInput_0
{
    float2 a_pos_0 [[attribute(0)]];
};


#line 9
struct tiles_vertex_shader_Out_0
{
    float4 gl_Position_2;
    float4 gl_FragCoord_2;
};


#line 9
[[vertex]] VertexMain_Result_0 VertexMain(vertexInput_0 _S10 [[stage_in]])
{

#line 33
    float4 _S11 = float4(0.0) ;

#line 33
    thread tiles_vertex_shader_Out_0 o_1;

#line 33
    (&o_1)->gl_Position_2 = _S11;

#line 33
    (&o_1)->gl_FragCoord_2 = _S11;
    (&o_1)->gl_Position_2 = float4(_S10.a_pos_0.x, _S10.a_pos_0.y, 0.0, 1.0);

#line 34
    thread VertexMain_Result_0 _S12;

#line 34
    (&_S12)->gl_Position_1 = o_1.gl_Position_2;

#line 34
    (&_S12)->gl_FragCoord_1 = o_1.gl_FragCoord_2;

#line 34
    return _S12;
}

