HEADLESS_IR_DIR :: ".build/headless_ir";
HEADLESS_IR_INTERMEDIATE_DIR :: ".build/ir_intermediate";

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

write_and_compile_metal_if_macos :: (path: string, source: string) {
  #if OS == .MACOS {
    if !write_entire_file(path, source) fail("Could not write %", path);
    compile_metal(path);
  }
}

Vector2 :: struct { x, y: float; }
Vector3 :: struct { x, y, z: float; }
Vector4 :: struct { x, y, z, w: float; }

IR_Headless_Project_Params :: struct {
  camera_pos_proj_x: Vector4;
  camera_right_proj_y: Vector4;
  camera_up_near: Vector4;
  camera_forward_far: Vector4;
}

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

ir_headless_project_camera_like :: (x: float, y: float, using params: *IR_Headless_Project_Params) -> Vector4 {
  sx := camera_pos_proj_x.w;
  sy := camera_right_proj_y.w;
  return .{x * sx, y * sy, 0.0, 1.0};
}

ir_headless_vertex_using_pointer_helper_main :: (using input: IR_Headless_Vertex_In, params: *IR_Headless_Project_Params) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  position = ir_headless_project_camera_like(a_pos.x, a_pos.y, params);
  color = Vector4.{1.0, 0.5, 0.0, 1.0};
  return out;
} @vertex_shader

ir_headless_fn_alias_leaf :: (x: float) -> float {
  return x * 0.5;
}

ir_headless_fn_alias_global :: ir_headless_fn_alias_leaf;

ir_headless_vertex_local_fn_alias_main :: (using input: IR_Headless_Vertex_In, using un: IR_Headless_Vertex_Uniforms) -> IR_Headless_Vertex_Out {
  using out: IR_Headless_Vertex_Out;
  px := ir_headless_fn_alias_global(a_pos.x);
  position = Vector4.{px, a_pos.y, 0.0, 1.0};
  color = Vector4.{0.4, 0.8, 0.2, 1.0};
  return out;
} @vertex_shader

IR_Headless_Fragment_Out :: struct {
  out_color: Vector4; @semantic_SV_Target0
}

IR_Headless_Bindless_Params :: struct {
  texture_index: u32;
  sampler_index: u32;
}

IR_Headless_Fragment_Vec3_Params :: struct {
  bias: Vector3;
  intensity: float;
}

IR_Headless_Fragment_Layout_Params :: struct {
  gain: float;
  _pad0_x: float;
  _pad0_y: float;
  _pad0_z: float;
  tint: Vector4;
}

IR_Headless_Fragment_Casted_Subscript_Params :: struct {
  packed: [2] Vector4;
}

IR_Headless_Fragment_Using_Pointer_Params :: struct {
  gain: float;
  _pad0_x: float;
  _pad0_y: float;
  _pad0_z: float;
}

IR_Headless_Fragment_Nested_Core :: struct {
  tint: Vector4;
  mix_gain: float;
  _pad0_x: float;
  _pad0_y: float;
  _pad0_z: float;
}

IR_Headless_Fragment_Nested_Params :: struct {
  gain: float;
  _pad0_x: float;
  _pad0_y: float;
  _pad0_z: float;
  core: IR_Headless_Fragment_Nested_Core;
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
IR_Headless_Fixed_Pointer_Count :: 64;

IR_Headless_Compute_Sim_Params :: struct {
  src: *IR_Headless_Compute_Boid_State;
  dst: *IR_Headless_Compute_Boid_State;
}

IR_Headless_Float4_Alias :: struct {
  x, y, z, w: float;
}

IR_Headless_Compute_Alias_Item :: struct {
  center_radius: IR_Headless_Float4_Alias;
  delta_pad: IR_Headless_Float4_Alias;
}

IR_Headless_Compute_Alias_Root :: struct {
  items: *IR_Headless_Compute_Alias_Item;
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

ir_headless_fragment_vec3_params_main :: (using input: IR_Headless_Vertex_Out, params: *IR_Headless_Fragment_Vec3_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = Vector4.{
    input.color.x * params.intensity + params.bias.x,
    input.color.y * params.intensity + params.bias.y,
    input.color.z * params.intensity + params.bias.z,
    1.0
  };
  return out;
} @fragment_shader

ir_headless_fragment_layout_params_main :: (using input: IR_Headless_Vertex_Out, params: IR_Headless_Fragment_Layout_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = Vector4.{
    input.color.x * params.gain + params.tint.x,
    input.color.y * params.gain + params.tint.y,
    input.color.z * params.gain + params.tint.z,
    1.0
  };
  return out;
} @fragment_shader

ir_headless_fragment_casted_subscript_params_main :: (using input: IR_Headless_Vertex_Out, params: *IR_Headless_Fragment_Casted_Subscript_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  i: u32 = 0;
  if input.position.x > 0.0 i = 1;
  out_color = params.packed[i];
  return out;
} @fragment_shader

ir_headless_apply_using_pointer_gain :: (x: float, using params: *IR_Headless_Fragment_Using_Pointer_Params) -> float {
  return x * gain;
}

ir_headless_fragment_using_pointer_params_main :: (using input: IR_Headless_Vertex_Out, params: *IR_Headless_Fragment_Using_Pointer_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  boosted := ir_headless_apply_using_pointer_gain(input.color.x + 0.25, params);
  out_color = Vector4.{boosted, input.color.y, input.color.z, 1.0};
  return out;
} @fragment_shader

ir_headless_fragment_nested_params_main :: (using input: IR_Headless_Vertex_Out, params: *IR_Headless_Fragment_Nested_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  i := cast(u32) (input.position.x > 0.0);
  f := cast(float) i;
  extra := params.core.mix_gain + f * 0.01;
  out_color = Vector4.{
    input.color.x * params.gain + extra,
    input.color.y * params.gain + extra,
    input.color.z * params.gain + extra,
    1.0,
  };
  return out;
} @fragment_shader

ir_headless_fragment_casted_fixed_alias_params_main :: (using input: IR_Headless_Vertex_Out, params: *IR_Headless_Fragment_Casted_Subscript_Params) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  v := (cast(*[2] Vector4) params).*[1];
  out_color = Vector4.{v.x + input.color.x * 0.0, v.y, v.z, v.w};
  return out;
} @fragment_shader

ir_headless_fragment_helpers_main :: (using input: IR_Headless_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = Vector4.{ir_headless_fragment_boost(input.color.x), input.color.y, input.color.z, input.color.w};
  return out;
} @fragment_shader

ir_headless_fragment_call_member_main :: (using input: IR_Headless_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  x := ir_headless_make_vec4(input.color.x).x;
  y := ir_headless_make_vec4(input.color.x).y;
  z := ir_headless_make_vec4(input.color.x).z;
  a := ir_headless_make_vec4(input.color.w).x;
  out_color = Vector4.{x, y, z, a};
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

ir_headless_compute_alias_layout_main :: (using input: IR_Headless_Compute_In, data: *IR_Headless_Compute_Alias_Root) {
  if thread_id.x < 64 {
    i := thread_id.x;
    cx := data.items[i].center_radius.x;
    dy := data.items[i].delta_pad.y;
    data.items[i].center_radius.x = cx + 1.0;
    data.items[i].delta_pad.y = dy - 0.5;
  }
} @compute_shader

ir_headless_compute_casted_struct_subscript_main :: (using input: IR_Headless_Compute_In, data: *IR_Headless_Compute_Alias_Root) {
  if thread_id.x < 64 {
    i := thread_id.x;
    x := (cast(*[IR_Headless_Fixed_Pointer_Count] IR_Headless_Compute_Alias_Item) data.items).*[i].center_radius.x;
    data.items[i].center_radius.x = x + 0.25;
  }
} @compute_shader

ir_headless_helper_fixed_array_x :: (state: *[IR_Headless_Fixed_Pointer_Count] Vector4, i: u32) -> float {
  return state.*[i].x;
}

ir_headless_compute_fixed_array_pointer_helper_main :: (using input: IR_Headless_Compute_In, table: *Vector4) {
  if thread_id.x < IR_Headless_Fixed_Pointer_Count {
    i := thread_id.x;
    x := ir_headless_helper_fixed_array_x(cast(*[IR_Headless_Fixed_Pointer_Count] Vector4) table, i);
    v := table[i];
    table[i] = Vector4.{x + 1.0, v.y, v.z, v.w};
  }
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

ir_headless_make_vec4 :: (x: float) -> Vector4 {
  return Vector4.{x, x + 0.25, x + 0.5, 1.0};
}

#run,stallable {
  if !make_directory_if_it_does_not_exist(HEADLESS_IR_DIR, recursive=true) {
    fail("Could not create %", HEADLESS_IR_DIR);
  }

  metal_vertex := get_transpiled(.METAL, ir_headless_vertex_main);
  check_generated_file_contains(tprint("%/ir_headless_vertex_main_vert.spvasm", HEADLESS_IR_INTERMEDIATE_DIR), "OpEntryPoint Vertex", "generated vertex SPIR-V text output");

  vertex_path := tprint("%/ir_vertex_only.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(vertex_path, metal_vertex);

  metal_vertex_math := get_transpiled(.METAL, ir_headless_vertex_math_main);
  check_contains(metal_vertex_math, "+", "math vertex metal output");
  check_contains(metal_vertex_math, "*", "math vertex metal output");
  math_path := tprint("%/ir_vertex_math.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(math_path, metal_vertex_math);

  metal_vertex_helpers := get_transpiled(.METAL, ir_headless_vertex_helpers_main);
  check_contains(metal_vertex_helpers, "0.25", "vertex helper metal output");
  check_contains(metal_vertex_helpers, "0.5", "vertex helper metal output");
  helper_vert_path := tprint("%/ir_vertex_helpers.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(helper_vert_path, metal_vertex_helpers);

  metal_vertex_uint_div := get_transpiled(.METAL, ir_headless_vertex_uint_div_main);
  check_contains(metal_vertex_uint_div, "/", "uint division vertex metal output");
  uint_div_vert_path := tprint("%/ir_vertex_uint_div.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(uint_div_vert_path, metal_vertex_uint_div);

  vulkan_vertex_helpers := get_transpiled(.VULKAN_GLSL, ir_headless_vertex_helpers_main);
  check_contains(vulkan_vertex_helpers, "#version", "vertex helper Vulkan GLSL output");
  check_contains(vulkan_vertex_helpers, "0.25", "vertex helper Vulkan GLSL output");
  check_contains(vulkan_vertex_helpers, "void main()", "vertex helper Vulkan GLSL output");

  metal_fragment := get_transpiled(.METAL, ir_headless_fragment_main);
  check_contains(metal_fragment, "fragment", "fragment metal output");
  check_generated_file_contains(tprint("%/ir_headless_fragment_main_frag.spvasm", HEADLESS_IR_INTERMEDIATE_DIR), "OpEntryPoint Fragment", "generated fragment SPIR-V text output");
  frag_path := tprint("%/ir_fragment_only.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(frag_path, metal_fragment);

  metal_fragment_return_note := get_transpiled(.METAL, ir_headless_fragment_return_note_main);
  check_contains(metal_fragment_return_note, "fragment", "fragment return-note metal output");
  check_contains(metal_fragment_return_note, "[[color(0)]]", "fragment return-note metal output");
  check_generated_file_contains(tprint("%/ir_headless_fragment_return_note_main_frag.spvasm", HEADLESS_IR_INTERMEDIATE_DIR), "Location 0", "fragment return-note SPIR-V text output");
  frag_return_note_path := tprint("%/ir_fragment_return_note.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(frag_return_note_path, metal_fragment_return_note);

  metal_fragment_helpers := get_transpiled(.METAL, ir_headless_fragment_helpers_main);
  check_contains(metal_fragment_helpers, "0.1", "fragment helper metal output");
  helper_frag_path := tprint("%/ir_fragment_helpers.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(helper_frag_path, metal_fragment_helpers);

  metal_fragment_call_member := get_transpiled(.METAL, ir_headless_fragment_call_member_main);
  check_contains(metal_fragment_call_member, "fragment", "fragment call-member metal output");
  check_generated_file_contains(tprint("%/ir_headless_fragment_call_member_main_frag.spvasm", HEADLESS_IR_INTERMEDIATE_DIR),
                               "OpCompositeExtract",
                               "fragment call-member SPIR-V text output");
  call_member_frag_path := tprint("%/ir_fragment_call_member.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(call_member_frag_path, metal_fragment_call_member);

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
  check_generated_file_contains(tprint("%/ir_headless_fragment_bindless_main_frag.spvasm", HEADLESS_IR_INTERMEDIATE_DIR),
                               "OpImageSampleImplicitLod",
                               "bindless fragment SPIR-V text output");
  check_generated_file_contains(tprint("%/ir_headless_fragment_bindless_main_frag.spvasm", HEADLESS_IR_INTERMEDIATE_DIR),
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
  write_and_compile_metal_if_macos(anon_frag_path, metal_fragment_anonymous);

  metal_compute_root := get_transpiled(.METAL, ir_headless_compute_root_struct_main);
  check_contains(metal_compute_root, "kernel", "compute root struct metal output");
  check_contains(metal_compute_root, "buffer(0)", "compute root struct metal output");
  compute_root_path := tprint("%/ir_compute_root_struct.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_root_path, metal_compute_root);

  metal_compute_pingpong := get_transpiled(.METAL, ir_headless_compute_pingpong_root_main);
  check_contains(metal_compute_pingpong, "kernel", "compute pingpong root struct metal output");
  check_contains(metal_compute_pingpong, "buffer(0)", "compute pingpong root struct metal output");
  check_contains(metal_compute_pingpong, "buffer(1)", "compute pingpong root struct metal output");
  compute_pingpong_path := tprint("%/ir_compute_pingpong_root_struct.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_pingpong_path, metal_compute_pingpong);

  metal_compute_member_subscript_struct_init := get_transpiled(.METAL, ir_headless_compute_member_subscript_struct_init_main);
  check_contains(metal_compute_member_subscript_struct_init, "kernel", "compute member-subscript struct-init metal output");
  check_contains(metal_compute_member_subscript_struct_init, "buffer(0)", "compute member-subscript struct-init metal output");
  check_contains(metal_compute_member_subscript_struct_init, "buffer(1)", "compute member-subscript struct-init metal output");
  compute_member_subscript_struct_init_path := tprint("%/ir_compute_member_subscript_struct_init.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_member_subscript_struct_init_path, metal_compute_member_subscript_struct_init);

  metal_compute_fixed_array_vector2 := get_transpiled(.METAL, ir_headless_compute_fixed_array_vector2_main);
  check_contains(metal_compute_fixed_array_vector2, "kernel", "compute fixed-array vector2 metal output");
  compute_fixed_array_vector2_path := tprint("%/ir_compute_fixed_array_vector2.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_fixed_array_vector2_path, metal_compute_fixed_array_vector2);

  metal_compute_alias_layout := get_transpiled(.METAL, ir_headless_compute_alias_layout_main);
  check_contains(metal_compute_alias_layout, "kernel", "compute alias-layout metal output");
  check_contains(metal_compute_alias_layout, "buffer(0)", "compute alias-layout metal output");
  compute_alias_layout_path := tprint("%/ir_compute_alias_layout.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_alias_layout_path, metal_compute_alias_layout);

  metal_compute_casted_struct_subscript := get_transpiled(.METAL, ir_headless_compute_casted_struct_subscript_main);
  check_contains(metal_compute_casted_struct_subscript, "kernel", "compute casted-struct-subscript metal output");
  check_contains(metal_compute_casted_struct_subscript, "buffer(0)", "compute casted-struct-subscript metal output");
  compute_casted_struct_subscript_path := tprint("%/ir_compute_casted_struct_subscript.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_casted_struct_subscript_path, metal_compute_casted_struct_subscript);

  metal_compute_fixed_array_pointer_helper := get_transpiled(.METAL, ir_headless_compute_fixed_array_pointer_helper_main);
  check_contains(metal_compute_fixed_array_pointer_helper, "kernel", "compute fixed-array-pointer-helper metal output");
  check_contains(metal_compute_fixed_array_pointer_helper, "buffer(0)", "compute fixed-array-pointer-helper metal output");
  compute_fixed_array_pointer_helper_path := tprint("%/ir_compute_fixed_array_pointer_helper.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(compute_fixed_array_pointer_helper_path, metal_compute_fixed_array_pointer_helper);

  metal_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_main);
  check_contains(metal_pair, "vertex", "pair metal output");
  check_contains(metal_pair, "fragment", "pair metal output");
  check_generated_file_contains(tprint("%/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_main_pair.spvasm", HEADLESS_IR_INTERMEDIATE_DIR), "OpEntryPoint Vertex", "generated pair SPIR-V text output");
  check_generated_file_contains(tprint("%/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_main_pair.spvasm", HEADLESS_IR_INTERMEDIATE_DIR), "OpEntryPoint Fragment", "generated pair SPIR-V text output");
  pair_path := tprint("%/ir_pair.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(pair_path, metal_pair);

  uint_div_pair := get_transpiled(.METAL, ir_headless_vertex_uint_div_main, ir_headless_fragment_main);
  check_contains(uint_div_pair, "vertex", "uint division pair metal output");
  check_contains(uint_div_pair, "fragment", "uint division pair metal output");
  uint_div_pair_path := tprint("%/ir_pair_uint_div.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(uint_div_pair_path, uint_div_pair);

  using_pointer_helper_pair := get_transpiled(.METAL, ir_headless_vertex_using_pointer_helper_main, ir_headless_fragment_main);
  check_contains(using_pointer_helper_pair, "vertex", "using-pointer helper pair metal output");
  check_contains(using_pointer_helper_pair, "fragment", "using-pointer helper pair metal output");
  using_pointer_helper_pair_path := tprint("%/ir_pair_using_pointer_helper.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(using_pointer_helper_pair_path, using_pointer_helper_pair);

  local_fn_alias_pair := get_transpiled(.METAL, ir_headless_vertex_local_fn_alias_main, ir_headless_fragment_main);
  check_contains(local_fn_alias_pair, "vertex", "local-fn-alias helper pair metal output");
  check_contains(local_fn_alias_pair, "fragment", "local-fn-alias helper pair metal output");
  local_fn_alias_pair_path := tprint("%/ir_pair_local_fn_alias_helper.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(local_fn_alias_pair_path, local_fn_alias_pair);

  position_semantic_pair := get_transpiled(.METAL, ir_headless_vertex_position_semantic_main, ir_headless_fragment_position_semantic_main);
  check_contains(position_semantic_pair, "vertex", "position-semantic pair metal output");
  check_contains(position_semantic_pair, "fragment", "position-semantic pair metal output");
  position_semantic_pair_path := tprint("%/ir_pair_position_semantic.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(position_semantic_pair_path, position_semantic_pair);

  anon_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_anonymous_main);
  check_contains(anon_pair, "vertex", "anonymous pair metal output");
  check_contains(anon_pair, "fragment", "anonymous pair metal output");
  check_contains(anon_pair, "[[color(0)]]", "anonymous pair metal output");
  anon_pair_path := tprint("%/ir_pair_anonymous_fragment.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(anon_pair_path, anon_pair);

  boids_pair := get_transpiled(.METAL, ir_headless_boids_vertex_main, ir_headless_boids_fragment_main);
  check_contains(boids_pair, "vertex", "boids-like pair metal output");
  check_contains(boids_pair, "fragment", "boids-like pair metal output");
  check_contains(boids_pair, "[[vertex_id]]", "boids-like pair metal output");
  check_contains(boids_pair, "[[instance_id]]", "boids-like pair metal output");
  boids_pair_path := tprint("%/ir_boids_like_pair.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(boids_pair_path, boids_pair);

  _ = get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_vec3_params_main);
  vec3_params_pair_path := ".generated_shaders/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_vec3_params_main.metal";
  check_generated_file_contains(vec3_params_pair_path, "fragment", "vec3 fragment-params pair metal output");
  #if OS == .MACOS compile_metal(vec3_params_pair_path);

  layout_params_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_layout_params_main);
  check_contains(layout_params_pair, "fragment", "layout-validated fragment-params pair metal output");
  layout_params_pair_path := tprint("%/ir_pair_fragment_layout_params.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(layout_params_pair_path, layout_params_pair);

  casted_subscript_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_casted_subscript_params_main);
  check_contains(casted_subscript_pair, "fragment", "casted-subscript fragment-params pair metal output");
  casted_subscript_pair_path := tprint("%/ir_pair_fragment_casted_subscript_params.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(casted_subscript_pair_path, casted_subscript_pair);

  using_pointer_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_using_pointer_params_main);
  check_contains(using_pointer_pair, "fragment", "using-pointer fragment-params pair metal output");
  using_pointer_pair_path := tprint("%/ir_pair_fragment_using_pointer_params.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(using_pointer_pair_path, using_pointer_pair);

  nested_params_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_nested_params_main);
  check_contains(nested_params_pair, "fragment", "nested fragment-params pair metal output");
  check_generated_file_contains(tprint("%/transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_nested_params_main_pair.spvasm",
                                       HEADLESS_IR_INTERMEDIATE_DIR),
                               "OpSelect",
                               "nested fragment-params pair bool-to-u32 cast SPIR-V output");
  nested_params_pair_path := tprint("%/ir_pair_fragment_nested_params.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(nested_params_pair_path, nested_params_pair);

  casted_alias_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_casted_fixed_alias_params_main);
  check_contains(casted_alias_pair, "fragment", "casted-fixed-alias fragment-params pair metal output");
  casted_alias_pair_path := tprint("%/ir_pair_fragment_casted_fixed_alias_params.metal", HEADLESS_IR_DIR);
  write_and_compile_metal_if_macos(casted_alias_pair_path, casted_alias_pair);

  log("IR headless runner passed. Outputs in %", HEADLESS_IR_DIR);
}

main :: () {}

#scope_file
#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import,file "../module.jai";
#import,dir "../modules/ir_pipe";
