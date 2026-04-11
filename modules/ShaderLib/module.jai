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

decode_bc5_normal :: inline (encoded: Vector2) -> Vector3 {
    normal_xy := encoded * 2.0 - 1.0;
    normal_xy_len2 := dot(normal_xy, normal_xy);
    normal_z_sq := 1.0 - normal_xy_len2;
    if normal_z_sq < 0.0 normal_z_sq = 0.0;
    normal_z := sqrt(normal_z_sq);
    return normalize(.{normal_xy.x, normal_xy.y, normal_z});
}

decode_bc5_normal :: inline (encoded: Vector3) -> Vector3 {
    return decode_bc5_normal(.{encoded.x, encoded.y});
}

decode_bc5_normal :: inline (encoded: Vector4) -> Vector3 {
    return decode_bc5_normal(.{encoded.x, encoded.y});
}

hash01 :: (i: u32) -> float {
    return hash01(cast(float)i);
}

hash01 :: (seed: float) -> float {
    x := sin(seed * 12.9898 + 78.233) * 43758.547;
    return x - floor(x);
}

hash01 :: (i: u32, pos: Vector2) -> float {
    return hash01(cast(float)i, pos);
}

hash01 :: (i: float, pos: Vector2) -> float {
    k0: float = 12.9898;
    k1: float = 78.233;
    k2: float = 37.719;
    k3: float = 43758.547;
    n := sin(pos.x * k0 + pos.y * k1 + cast(float) i * k2);
    x := n * k3;
    return x - floor(x);
}

#scope_file
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
