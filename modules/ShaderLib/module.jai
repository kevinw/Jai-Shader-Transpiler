Fullscreen_Tri_Vert_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Fullscreen_Tri_Vert_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

fullscreen_tri_vert :: (using in: Fullscreen_Tri_Vert_In) -> Fullscreen_Tri_Vert_Out {
    tri_vertices :: Vector2.[ {-1, -1}, {3, -1}, {-1, 3} ];
    pos := tri_vertices[vertex_id];
    return {
        gl_Position = .{pos.x, pos.y, 0.0, 1.0},
        uv = pos * 0.5 + 0.5,
    };
} @vertex_shader

#scope_file
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
