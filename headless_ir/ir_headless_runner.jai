#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import,file "../module.jai";

HEADLESS_IR_DIR :: ".build/headless_ir";

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_contains :: (source: string, pattern: string, where: string) {
  ok, _ := contains(source, pattern);
  if !ok fail("Expected '%' in %", pattern, where);
}

check_generated_file_contains :: (path: string, pattern: string, where: string) {
  if !file_exists(path) fail("Expected generated file missing: %", path);
  source, ok := read_entire_file(path);
  if !ok fail("Could not read %", path);
  check_contains(source, pattern, where);
}

compile_metal :: (path: string) {
  ok := ir_run_command_checked(tprint("xcrun metal %", path),
                               .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", path, "-o", tprint("%.air", path)]);
  if !ok fail("Failed to compile Metal output: %", path);
}

Vector2 :: struct { x, y: float; }
Vector4 :: struct { x, y, z, w: float; }

sample_2d :: (texture_index: u32, sampler_index: u32, uv: Vector2) -> Vector4 {
  _ = texture_index;
  _ = sampler_index;
  _ = uv;
  return .{};
}

IR_Headless_Vertex_In :: struct {
  a_pos: Vector2; @semantic_ATTRIBUTE0
  vertex_id: u32; @semantic_SV_VertexID
  instance_id: u32; @semantic_SV_InstanceID
}

IR_Headless_Vertex_Uniforms :: struct {}

IR_Headless_Vertex_Out :: struct {
  position: Vector4; @semantic_SV_Position
  color: Vector4; @semantic_COLOR0
}

ir_headless_vertex_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  position = Vector4.{a_pos.x, a_pos.y, 0.0, 1.0};
  color = Vector4.{1.0, 0.0, 0.0, 1.0};
  _ = vertex_id;
  _ = instance_id;
  return out;
} @vertex_shader

ir_headless_vertex_math_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  position = Vector4.{a_pos.x + 0.25, a_pos.y * 2.0, 0.0, 1.0};
  color = Vector4.{0.0, 1.0, 0.0, 1.0};
  return out;
} @vertex_shader

ir_headless_vertex_helpers_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  position = Vector4.{a_pos.x, a_pos.y, 0.0, 1.0};
  color = Vector4.{ir_headless_chain_mid(a_pos.x), ir_headless_chain_mid(a_pos.x) * 0.5, 0.0, 1.0};
  return out;
} @vertex_shader

ir_headless_vertex_uint_div_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  half_id := vertex_id / 2;
  t := cast(float) half_id * 0.1;
  position = Vector4.{a_pos.x + t, a_pos.y, 0.0, 1.0};
  color = Vector4.{t, 0.0, 1.0, 1.0};
  return out;
} @vertex_shader

IR_Headless_Fragment_Out :: struct {
  out_color: Vector4; @semantic_SV_Target0
}

IR_Headless_Bindless_Params :: struct {
  texture_index: u32;
  sampler_index: u32;
}

IR_Headless_Position_Semantic_Vertex_Out :: struct {
  gl_Position: Vector4; @position
  color: Vector4;
}


IR_Headless_Compute_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
}

UVector3 :: struct {
  x, y, z: u32;
}

IR_Headless_Compute_Root :: struct {
  values: *u32;
}

IR_Headless_Compute_PingPong_Root :: struct {
  src: *u32;
  dst: *u32;
}

IR_Headless_Compute_Boid_State :: struct {
  pos: Vector2;
  vel: Vector2;
}

IR_Headless_Vector_Field_Count :: 65536;

IR_Headless_Compute_Sim_Params :: struct {
  src: *IR_Headless_Compute_Boid_State;
  dst: *IR_Headless_Compute_Boid_State;
}

IR_Boids_Vertex_Params :: struct {
  positions: *Vector2;
  instances: *Vector2;
}

IR_Boids_Fragment_Params :: struct {
  color: *float;
}

IR_Boids_Params :: struct {
  vertex_data: *IR_Boids_Vertex_Params;
  fragment_data: *IR_Boids_Fragment_Params;
}

IR_Boids_Vertex_In :: struct {
  vertex_id: u32; @semantic_SV_VertexID
  instance_id: u32; @semantic_SV_InstanceID
}

ir_headless_boids_vertex_main :: (using input: IR_Boids_Vertex_In, params: IR_Boids_Params) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  instance_position := params.vertex_data.instances[instance_id];
  base := params.vertex_data.positions[vertex_id];
  pos := Vector2.{base.x + instance_position.x, base.y + instance_position.y};
  position = Vector4.{pos.x, pos.y, 0.0, 1.0};
  color = Vector4.{1.0, 0.0, 0.0, 1.0};
  return out;
} @vertex_shader

ir_headless_boids_fragment_main :: (using input: IR_Headless_Vertex_Out, params: IR_Boids_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = Vector4.{params.fragment_data.color[0], params.fragment_data.color[1], params.fragment_data.color[2], 1.0};
  return out;
} @fragment_shader

ir_headless_fragment_main :: (using input: IR_Headless_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = input.color;
  return out;
} @fragment_shader

ir_headless_fragment_bindless_main :: (using input: IR_Headless_Vertex_Out, params: IR_Headless_Bindless_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  uv := Vector2.{input.position.x, input.position.y};
  out_color = sample_2d(params.texture_index, params.sampler_index, uv);
  return out;
} @fragment_shader

ir_headless_fragment_helpers_main :: (using input: IR_Headless_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = Vector4.{ir_headless_fragment_boost(input.color.x), input.color.y, input.color.z, input.color.w};
  return out;
} @fragment_shader

ir_headless_fragment_return_note_main :: (using input: IR_Headless_Vertex_Out) -> Vector4 @SV_Target {
  _ = input;
  return Vector4.{1.0, 0.0, 0.0, 1.0};
} @fragment_shader

ir_headless_fragment_anonymous_main :: (using input: IR_Headless_Vertex_Out) -> struct { out_color: Vector4; } {
  return .{
    out_color = Vector4.{input.color.x, input.color.y, input.color.z, input.color.w},
  };
} @fragment_shader

ir_headless_vertex_position_semantic_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Position_Semantic_Vertex_Out {
  using out: IR_Headless_Position_Semantic_Vertex_Out;
  gl_Position = Vector4.{a_pos.x, a_pos.y, 0.0, 1.0};
  color = Vector4.{0.25, 0.5, 0.75, 1.0};
  return out;
} @vertex_shader

ir_headless_fragment_position_semantic_main :: (using input: IR_Headless_Position_Semantic_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = input.color;
  return out;
} @fragment_shader


ir_headless_compute_root_struct_main :: (using input: IR_Headless_Compute_In, data: *IR_Headless_Compute_Root) {
  if thread_id.x < 64 {
    data.values[thread_id.x] = data.values[thread_id.x] + 1;
  }
} @compute_shader

ir_headless_compute_pingpong_root_main :: (using input: IR_Headless_Compute_In, data: *IR_Headless_Compute_PingPong_Root) {
  if thread_id.x < 64 {
    data.dst[thread_id.x] = data.src[thread_id.x] + 2;
  }
} @compute_shader

ir_headless_compute_member_subscript_struct_init_main :: (using input: IR_Headless_Compute_In, sim: *IR_Headless_Compute_Sim_Params) {
  if thread_id.x < 64 {
    b := sim.src[thread_id.x];
    sim.dst[thread_id.x].pos = b.pos;
    sim.dst[thread_id.x].vel = b.vel;
  }
} @compute_shader

ir_headless_compute_fixed_array_vector2_main :: (using input: IR_Headless_Compute_In, state: *[IR_Headless_Vector_Field_Count] Vector2) {
  if thread_id.x < 1 {
    probe := thread_id.x + 1;
    _ = probe;
  }
  _ = state;
} @compute_shader

// Intentionally declared after the entry points above to validate order-independence.
ir_headless_chain_leaf :: (x: float) -> float {
  return x * 2.0;
}

ir_headless_chain_mid :: (x: float) -> float {
  return ir_headless_chain_leaf(x) + 0.25;
}

ir_headless_fragment_boost :: (x: float) -> float {
  return x + 0.1;
}

#run,stallable {
  if !make_directory_if_it_does_not_exist(HEADLESS_IR_DIR, recursive=true) {
    fail("Could not create %", HEADLESS_IR_DIR);
  }

  metal_vertex := get_transpiled(.METAL, ir_headless_vertex_main);
  check_generated_file_contains(".build/ir_slang/ir_headless_vertex_main_vert.spvasm", "OpEntryPoint Vertex", "generated vertex SPIR-V text output");

  vertex_path := tprint("%/ir_vertex_only.metal", HEADLESS_IR_DIR);
  if !write_entire_file(vertex_path, metal_vertex) fail("Could not write %", vertex_path);
  #if OS == .MACOS {
    compile_metal(vertex_path);
  } else {
    log("Skipping Metal compile checks on %.", OS);
  }

  metal_vertex_math := get_transpiled(.METAL, ir_headless_vertex_math_main);
  check_contains(metal_vertex_math, "+", "math vertex metal output");
  check_contains(metal_vertex_math, "*", "math vertex metal output");
  math_path := tprint("%/ir_vertex_math.metal", HEADLESS_IR_DIR);
  if !write_entire_file(math_path, metal_vertex_math) fail("Could not write %", math_path);
  #if OS == .MACOS {
    compile_metal(math_path);
  }

  metal_vertex_helpers := get_transpiled(.METAL, ir_headless_vertex_helpers_main);
  check_contains(metal_vertex_helpers, "0.25", "vertex helper metal output");
  check_contains(metal_vertex_helpers, "0.5", "vertex helper metal output");
  helper_vert_path := tprint("%/ir_vertex_helpers.metal", HEADLESS_IR_DIR);
  if !write_entire_file(helper_vert_path, metal_vertex_helpers) fail("Could not write %", helper_vert_path);
  #if OS == .MACOS {
    compile_metal(helper_vert_path);
  }

  metal_vertex_uint_div := get_transpiled(.METAL, ir_headless_vertex_uint_div_main);
  check_contains(metal_vertex_uint_div, "/", "uint division vertex metal output");
  uint_div_vert_path := tprint("%/ir_vertex_uint_div.metal", HEADLESS_IR_DIR);
  if !write_entire_file(uint_div_vert_path, metal_vertex_uint_div) fail("Could not write %", uint_div_vert_path);
  #if OS == .MACOS {
    compile_metal(uint_div_vert_path);
  }

  vulkan_vertex_helpers := get_transpiled(.VULKAN_GLSL, ir_headless_vertex_helpers_main);
  check_contains(vulkan_vertex_helpers, "#version", "vertex helper Vulkan GLSL output");
  check_contains(vulkan_vertex_helpers, "0.25", "vertex helper Vulkan GLSL output");
  check_contains(vulkan_vertex_helpers, "void main()", "vertex helper Vulkan GLSL output");

  metal_fragment := get_transpiled(.METAL, ir_headless_fragment_main);
  check_contains(metal_fragment, "fragment", "fragment metal output");
  check_generated_file_contains(".build/ir_slang/ir_headless_fragment_main_frag.spvasm", "OpEntryPoint Fragment", "generated fragment SPIR-V text output");
  frag_path := tprint("%/ir_fragment_only.metal", HEADLESS_IR_DIR);
  if !write_entire_file(frag_path, metal_fragment) fail("Could not write %", frag_path);
  #if OS == .MACOS {
    compile_metal(frag_path);
  }

  metal_fragment_return_note := get_transpiled(.METAL, ir_headless_fragment_return_note_main);
  check_contains(metal_fragment_return_note, "fragment", "fragment return-note metal output");
  check_contains(metal_fragment_return_note, "[[color(0)]]", "fragment return-note metal output");
  check_generated_file_contains(".build/ir_slang/ir_headless_fragment_return_note_main_frag.spvasm", "Location 0", "fragment return-note SPIR-V text output");
  frag_return_note_path := tprint("%/ir_fragment_return_note.metal", HEADLESS_IR_DIR);
  if !write_entire_file(frag_return_note_path, metal_fragment_return_note) fail("Could not write %", frag_return_note_path);
  #if OS == .MACOS {
    compile_metal(frag_return_note_path);
  }

  metal_fragment_helpers := get_transpiled(.METAL, ir_headless_fragment_helpers_main);
  check_contains(metal_fragment_helpers, "0.1", "fragment helper metal output");
  helper_frag_path := tprint("%/ir_fragment_helpers.metal", HEADLESS_IR_DIR);
  if !write_entire_file(helper_frag_path, metal_fragment_helpers) fail("Could not write %", helper_frag_path);
  #if OS == .MACOS {
    compile_metal(helper_frag_path);
  }

  vulkan_fragment_helpers := get_transpiled(.VULKAN_GLSL, ir_headless_fragment_helpers_main);
  check_contains(vulkan_fragment_helpers, "#version", "fragment helper Vulkan GLSL output");
  check_contains(vulkan_fragment_helpers, "0.1", "fragment helper Vulkan GLSL output");
  check_contains(vulkan_fragment_helpers, "void main()", "fragment helper Vulkan GLSL output");

  vulkan_fragment_bindless := get_transpiled(.VULKAN_GLSL, ir_headless_fragment_bindless_main);
  check_contains(vulkan_fragment_bindless, "#version", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "sampler2D", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "sample_2d_textures[16]", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "sample_2d_samplers[16]", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "sample_2d_textures[min(params.texture_index, 15u)]", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "sample_2d_samplers[min(params.sampler_index, 15u)]", "bindless fragment Vulkan GLSL output");
  check_contains(vulkan_fragment_bindless, "texture(", "bindless fragment Vulkan GLSL output");
  check_generated_file_contains(".build/ir_slang/ir_headless_fragment_bindless_main_frag.spvasm",
                               "OpImageSampleImplicitLod",
                               "bindless fragment SPIR-V text output");
  check_generated_file_contains(".build/ir_slang/ir_headless_fragment_bindless_main_frag.spvasm",
                               " UMin ",
                               "bindless fragment SPIR-V text output");

  metal_fragment_bindless := get_transpiled(.METAL, ir_headless_fragment_bindless_main);
  check_contains(metal_fragment_bindless, "array<texture2d<float>, 16>", "bindless fragment metal output");
  check_contains(metal_fragment_bindless, "sample_2d_textures [[texture(1)]]", "bindless fragment metal output");
  check_contains(metal_fragment_bindless, "array<sampler, 16>", "bindless fragment metal output");
  check_contains(metal_fragment_bindless, "sample_2d_samplers [[sampler(0)]]", "bindless fragment metal output");

  metal_fragment_anonymous := get_transpiled(.METAL, ir_headless_fragment_anonymous_main);
  check_contains(metal_fragment_anonymous, "fragment", "anonymous fragment metal output");
  check_contains(metal_fragment_anonymous, "[[color(0)]]", "anonymous fragment metal output");
  anon_frag_path := tprint("%/ir_fragment_anonymous.metal", HEADLESS_IR_DIR);
  if !write_entire_file(anon_frag_path, metal_fragment_anonymous) fail("Could not write %", anon_frag_path);
  #if OS == .MACOS {
    compile_metal(anon_frag_path);
  }

  metal_compute_root := get_transpiled(.METAL, ir_headless_compute_root_struct_main);
  check_contains(metal_compute_root, "kernel", "compute root struct metal output");
  check_contains(metal_compute_root, "buffer(0)", "compute root struct metal output");
  compute_root_path := tprint("%/ir_compute_root_struct.metal", HEADLESS_IR_DIR);
  if !write_entire_file(compute_root_path, metal_compute_root) fail("Could not write %", compute_root_path);
  #if OS == .MACOS {
    compile_metal(compute_root_path);
  }

  metal_compute_pingpong := get_transpiled(.METAL, ir_headless_compute_pingpong_root_main);
  check_contains(metal_compute_pingpong, "kernel", "compute pingpong root struct metal output");
  check_contains(metal_compute_pingpong, "buffer(0)", "compute pingpong root struct metal output");
  check_contains(metal_compute_pingpong, "buffer(1)", "compute pingpong root struct metal output");
  compute_pingpong_path := tprint("%/ir_compute_pingpong_root_struct.metal", HEADLESS_IR_DIR);
  if !write_entire_file(compute_pingpong_path, metal_compute_pingpong) fail("Could not write %", compute_pingpong_path);
  #if OS == .MACOS {
    compile_metal(compute_pingpong_path);
  }

  metal_compute_member_subscript_struct_init := get_transpiled(.METAL, ir_headless_compute_member_subscript_struct_init_main);
  check_contains(metal_compute_member_subscript_struct_init, "kernel", "compute member-subscript struct-init metal output");
  check_contains(metal_compute_member_subscript_struct_init, "buffer(0)", "compute member-subscript struct-init metal output");
  check_contains(metal_compute_member_subscript_struct_init, "buffer(1)", "compute member-subscript struct-init metal output");
  compute_member_subscript_struct_init_path := tprint("%/ir_compute_member_subscript_struct_init.metal", HEADLESS_IR_DIR);
  if !write_entire_file(compute_member_subscript_struct_init_path, metal_compute_member_subscript_struct_init) fail("Could not write %", compute_member_subscript_struct_init_path);
  #if OS == .MACOS {
    compile_metal(compute_member_subscript_struct_init_path);
  }

  metal_compute_fixed_array_vector2 := get_transpiled(.METAL, ir_headless_compute_fixed_array_vector2_main);
  check_contains(metal_compute_fixed_array_vector2, "kernel", "compute fixed-array vector2 metal output");
  compute_fixed_array_vector2_path := tprint("%/ir_compute_fixed_array_vector2.metal", HEADLESS_IR_DIR);
  if !write_entire_file(compute_fixed_array_vector2_path, metal_compute_fixed_array_vector2) fail("Could not write %", compute_fixed_array_vector2_path);
  #if OS == .MACOS {
    compile_metal(compute_fixed_array_vector2_path);
  }

  metal_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_main);
  check_contains(metal_pair, "vertex", "pair metal output");
  check_contains(metal_pair, "fragment", "pair metal output");
  check_generated_file_contains(".build/ir_slang/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_main_pair.spvasm", "OpEntryPoint Vertex", "generated pair SPIR-V text output");
  check_generated_file_contains(".build/ir_slang/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_main_pair.spvasm", "OpEntryPoint Fragment", "generated pair SPIR-V text output");
  pair_path := tprint("%/ir_pair.metal", HEADLESS_IR_DIR);
  if !write_entire_file(pair_path, metal_pair) fail("Could not write %", pair_path);
  #if OS == .MACOS {
    compile_metal(pair_path);
  }

  uint_div_pair := get_transpiled(.METAL, ir_headless_vertex_uint_div_main, ir_headless_fragment_main);
  check_contains(uint_div_pair, "vertex", "uint division pair metal output");
  check_contains(uint_div_pair, "fragment", "uint division pair metal output");
  uint_div_pair_path := tprint("%/ir_pair_uint_div.metal", HEADLESS_IR_DIR);
  if !write_entire_file(uint_div_pair_path, uint_div_pair) fail("Could not write %", uint_div_pair_path);
  #if OS == .MACOS {
    compile_metal(uint_div_pair_path);
  }

  position_semantic_pair := get_transpiled(.METAL, ir_headless_vertex_position_semantic_main, ir_headless_fragment_position_semantic_main);
  check_contains(position_semantic_pair, "vertex", "position-semantic pair metal output");
  check_contains(position_semantic_pair, "fragment", "position-semantic pair metal output");
  position_semantic_pair_path := tprint("%/ir_pair_position_semantic.metal", HEADLESS_IR_DIR);
  if !write_entire_file(position_semantic_pair_path, position_semantic_pair) fail("Could not write %", position_semantic_pair_path);
  #if OS == .MACOS {
    compile_metal(position_semantic_pair_path);
  }

  anon_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_anonymous_main);
  check_contains(anon_pair, "vertex", "anonymous pair metal output");
  check_contains(anon_pair, "fragment", "anonymous pair metal output");
  check_contains(anon_pair, "[[color(0)]]", "anonymous pair metal output");
  anon_pair_path := tprint("%/ir_pair_anonymous_fragment.metal", HEADLESS_IR_DIR);
  if !write_entire_file(anon_pair_path, anon_pair) fail("Could not write %", anon_pair_path);
  #if OS == .MACOS {
    compile_metal(anon_pair_path);
  }

  boids_pair := get_transpiled(.METAL, ir_headless_boids_vertex_main, ir_headless_boids_fragment_main);
  check_contains(boids_pair, "vertex", "boids-like pair metal output");
  check_contains(boids_pair, "fragment", "boids-like pair metal output");
  check_contains(boids_pair, "[[vertex_id]]", "boids-like pair metal output");
  check_contains(boids_pair, "[[instance_id]]", "boids-like pair metal output");
  boids_pair_path := tprint("%/ir_boids_like_pair.metal", HEADLESS_IR_DIR);
  if !write_entire_file(boids_pair_path, boids_pair) fail("Could not write %", boids_pair_path);
  #if OS == .MACOS {
    compile_metal(boids_pair_path);
  }

  log("IR headless runner passed. Outputs in %", HEADLESS_IR_DIR);
}

main :: () {}
