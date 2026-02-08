#version 330 core
in vec2 a_pos;

uniform vec2 u_offsets[3];

out vec2 sample_offset;


void main() {
     vec2 positions[3] = vec2[](vec2(0.0, 0.5), vec2(-0.5, -0.5), vec2(0.5, -0.5));
     sample_offset = positions[0] + u_offsets[1];
     gl_Position = vec4(a_pos.x + positions[2].x, a_pos.y + u_offsets[2].y, 0.0, 1);
}

