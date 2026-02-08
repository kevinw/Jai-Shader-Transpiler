tiles_vertex_shader_string :: #string END
#version 330 core
in vec2 a_pos;




void main() {
     gl_Position = vec4(a_pos.x, a_pos.y, 0.0, 1);
}


END