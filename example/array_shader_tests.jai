Array_Test_Vertex_Uniforms :: struct {
  u_offsets: [3] Vector2;
}

Array_Test_Vertex_In :: struct {
  a_pos: Vector2;
}

Array_Test_Vertex_Out :: struct {
  gl_Position: Vector4; @position
  gl_FragCoord: Vector4; @frag_coord
  sample_offset: Vector2;
}

array_support_vertex_shader :: (using in: Array_Test_Vertex_In, using un: Array_Test_Vertex_Uniforms)
                                   -> Array_Test_Vertex_Out {
  using out: Array_Test_Vertex_Out;

  positions := Vector2.[
      { 0.0,  0.5},
      {-0.5, -0.5},
      { 0.5, -0.5},
  ];

  sample_offset = positions[0] + u_offsets[1];
  gl_Position = Vector4.{ a_pos.x + positions[2].x, a_pos.y + u_offsets[2].y, 0.0, 1.0 };
  return out;
} @vertex_shader


Array_Test_Fragment_Uniforms :: struct {
  u_palette: [2] Vector4;
}

Array_Test_Fragment_Out :: struct {
  out_color: Vector4;
}

array_support_fragment_shader :: (using in: Array_Test_Vertex_Out, using un: Array_Test_Fragment_Uniforms) -> Array_Test_Fragment_Out {
  using out: Array_Test_Fragment_Out;

  local_palette := Vector4.[
      { 1.0, 0.0, 0.0, 1.0 },
      { 0.0, 1.0, 0.0, 1.0 },
  ];

  out_color = local_palette[0] * (sample_offset.x + 0.5) + u_palette[1] * 0.5;
  return out;
} @fragment_shader
