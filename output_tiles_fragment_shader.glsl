tiles_fragment_shader_string :: #string END
#version 330 core

uniform vec2 u_resolution;
uniform float u_time;

out vec4 out_color;


void main() {
     float aspect_ratio = u_resolution.y / u_resolution.x;
     vec2 uv = vec2(gl_FragCoord.x, gl_FragCoord.y) / u_resolution.x;
     uv -= vec2(0.5, 0.5 * aspect_ratio);
     float rot = radians(-30 - u_time);
     mat2 rotation_matrix = mat2(cos(rot), -sin(rot), sin(rot), cos(rot));
     uv = rotation_matrix * uv;
     vec2 scaled_uv = 20 * uv;
     vec2 tile = fract(scaled_uv);
     float tile_dist = min(min(tile.x, 1 - tile.x), min(tile.y, 1 - tile.y));
     float square_dist = length(floor(scaled_uv));
     float edge = sin(u_time - square_dist * 20);
     edge = mod(edge * edge, edge / edge);
     float value = mix(tile_dist, 1 - tile_dist, step(1, edge));
     edge = pow(abs(1 - edge), 2.2) * 0.5;
     value = smoothstep(edge - 0.05, edge, 0.95 * value);
     value += square_dist * 0.1;
     value *= 0.8 - 0.2;
     out_color = vec4(pow(value, 2), pow(value, 1.5), pow(value, 1.2), 1);
}


END