#include <metal_stdlib>
using namespace metal;

inline float jai_radians(float v) { return v * 0.01745329251994329577f; }
inline float2 jai_radians(float2 v) { return v * 0.01745329251994329577f; }
inline float3 jai_radians(float3 v) { return v * 0.01745329251994329577f; }
inline float4 jai_radians(float4 v) { return v * 0.01745329251994329577f; }

struct VertexShader_In {
    float2 a_pos [[attribute(0)]];
};

struct VertexShader_Uniforms {
};

struct VertexShader_Out {
    float4 gl_Position [[position]];
    float4 gl_FragCoord [[user(gl_FragCoord)]];
};

struct FragmentShader_Uniforms {
    float2 u_resolution;
    float u_time;
};

struct FragmentShader_Out {
    float4 out_color [[color(0)]];
};


vertex VertexShader_Out VertexMain(VertexShader_In in [[stage_in]], constant VertexShader_Uniforms& un [[buffer(0)]]) {
     float2 a_pos = in.a_pos;
     float4 gl_Position;

     gl_Position = float4(a_pos.x, a_pos.y, 0.0, 1);
          VertexShader_Out out;
     out.gl_Position = gl_Position;
     out.gl_FragCoord = gl_Position;
     return out;
}

fragment FragmentShader_Out FragmentMain(VertexShader_Out in [[stage_in]], constant FragmentShader_Uniforms& un [[buffer(0)]]) {
     float4 gl_FragCoord = in.gl_FragCoord;
     float2 u_resolution = un.u_resolution;
     float u_time = un.u_time;
     float4 out_color;

     float aspect_ratio = u_resolution.y / u_resolution.x;
     float2 uv = gl_FragCoord.xy / u_resolution.x;
     uv -= float2(0.5, 0.5 * aspect_ratio);
     float rot = jai_radians(-30 - u_time);
     float2x2 rotation_matrix = float2x2(float2(cos(rot), -sin(rot)), float2(sin(rot), cos(rot)));
     uv = rotation_matrix * uv;
     float2 scaled_uv = 20 * uv;
     float2 tile = fract(scaled_uv);
     float tile_dist = min(min(tile.x, 1 - tile.x), min(tile.y, 1 - tile.y));
     float square_dist = length(floor(scaled_uv));
     float edge = sin(u_time - square_dist * 20);
     edge = fmod(edge * edge, edge / edge);
     float value = mix(tile_dist, 1 - tile_dist, step(1, edge));
     edge = pow(abs(1 - edge), 2.2) * 0.5;
     value = smoothstep(edge - 0.05, edge, 0.95 * value);
     value += square_dist * 0.1;
     value *= 0.8 - 0.2;
     out_color = float4(pow(value, 2), pow(value, 1.5), pow(value, 1.2), 1);
          FragmentShader_Out out;
     out.out_color = out_color;
     return out;
}

