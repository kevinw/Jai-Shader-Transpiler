#version 330 core
in vec2 sample_offset;

uniform vec4 u_palette[2];

out vec4 out_color;


void main() {
     vec4 local_palette[2] = vec4[](vec4(1, 0.0, 0.0, 1), vec4(0.0, 1, 0.0, 1));
     out_color = local_palette[0] * sample_offset.x + 0.5 + u_palette[1] * 0.5;
}

