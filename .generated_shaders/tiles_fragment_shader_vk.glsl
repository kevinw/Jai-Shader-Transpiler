// Generated from /Users/kev/src/peel/modules/Jai-Shader-Transpiler/example/vulkan_shaders.jai with (<<Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL>>)
#version 450

layout(set = 0, binding = 0, std140) uniform FragmentShaderVk_Uniforms_std140
{
    vec2 u_resolution;
    float u_time;
} un;

layout(location = 0) out vec4 entryPointParam_FragmentMain_out_color;

void main()
{
    float _47 = radians((-30.0) - un.u_time);
    float _49 = cos(_47);
    float _50 = sin(_47);
    vec2 scaled_uv = (mat2(vec2(_49, _50), vec2(-_50, _49)) * ((vec2(gl_FragCoord.xy) / vec2(un.u_resolution.x)) - vec2(0.5, 0.5 * (un.u_resolution.y / un.u_resolution.x)))) * 20.0;
    vec2 _59 = fract(scaled_uv);
    float _60 = _59.x;
    float _64 = _59.y;
    float _67 = min(min(_60, 1.0 - _60), min(_64, 1.0 - _64));
    float _69 = length(floor(scaled_uv));
    float _73 = sin(un.u_time - (_69 * 20.0));
    float _74 = _73 * _73;
    float _75 = _73 / _73;
    float _76 = _74 - _75 * trunc(_74 / _75);
    float edge = pow(abs(1.0 - _76), 2.2000000476837158203125) * 0.5;
    float value = (smoothstep(edge - 0.0500000007450580596923828125, edge, 0.949999988079071044921875 * mix(_67, 1.0 - _67, step(1.0, _76))) + (_69 * 0.100000001490116119384765625)) * 0.60000002384185791015625;
    entryPointParam_FragmentMain_out_color = vec4(pow(value, 2.0), pow(value, 1.5), pow(value, 1.2000000476837158203125), 1.0);
}

