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

compile_metal :: (path: string) {
  ok := ir_run_command_checked(tprint("xcrun metal %", path),
                               .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", path, "-o", tprint("%.air", path)]);
  if !ok fail("Failed to compile Metal output: %", path);
}

Vector2 :: struct { x, y: float; }
Vector4 :: struct { x, y, z, w: float; }

IR_Headless_Vertex_In :: struct {
  a_pos: Vector2; @semantic_POSITION
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

IR_Headless_Fragment_Out :: struct {
  out_color: Vector4; @semantic_SV_Target0
}

ir_headless_fragment_main :: (using input: IR_Headless_Vertex_Out) -> IR_Headless_Fragment_Out {
  using out: IR_Headless_Fragment_Out;
  out_color = input.color;
  return out;
} @fragment_shader

#run,stallable {
  if !make_directory_if_it_does_not_exist(HEADLESS_IR_DIR, recursive=true) {
    fail("Could not create %", HEADLESS_IR_DIR);
  }

  metal_vertex := get_transpiled(.METAL, ir_headless_vertex_main);
  check_contains(metal_vertex, "[[vertex_id]]", "vertex metal output");
  check_contains(metal_vertex, "[[instance_id]]", "vertex metal output");

  ir_slang_path := ".build/ir_slang/ir_headless_vertex_main_vert.slang";
  ir_slang_source, ir_slang_ok := read_entire_file(ir_slang_path);
  if !ir_slang_ok fail("Could not read %", ir_slang_path);
  check_contains(ir_slang_source, "generated_by_ir_pipeline", "generated slang output");

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

  metal_fragment := get_transpiled(.METAL, ir_headless_fragment_main);
  check_contains(metal_fragment, "fragment", "fragment metal output");
  ir_frag_slang_path := ".build/ir_slang/ir_headless_fragment_main_frag.slang";
  ir_frag_slang_source, ir_frag_ok := read_entire_file(ir_frag_slang_path);
  if !ir_frag_ok fail("Could not read %", ir_frag_slang_path);
  check_contains(ir_frag_slang_source, "generated_by_ir_pipeline", "generated fragment slang output");
  frag_path := tprint("%/ir_fragment_only.metal", HEADLESS_IR_DIR);
  if !write_entire_file(frag_path, metal_fragment) fail("Could not write %", frag_path);
  #if OS == .MACOS {
    compile_metal(frag_path);
  }

  metal_pair := get_transpiled(.METAL, ir_headless_vertex_main, ir_headless_fragment_main);
  check_contains(metal_pair, "vertex", "pair metal output");
  check_contains(metal_pair, "fragment", "pair metal output");
  ir_pair_slang_path := ".build/ir_slang/__get_transpiled_pair__metal_ir_headless_vertex_main_ir_headless_fragment_main_pair.slang";
  ir_pair_slang_source, ir_pair_ok := read_entire_file(ir_pair_slang_path);
  if !ir_pair_ok fail("Could not read %", ir_pair_slang_path);
  check_contains(ir_pair_slang_source, "generated_by_ir_pipeline", "generated pair slang output");
  pair_path := tprint("%/ir_pair.metal", HEADLESS_IR_DIR);
  if !write_entire_file(pair_path, metal_pair) fail("Could not write %", pair_path);
  #if OS == .MACOS {
    compile_metal(pair_path);
  }

  log("IR headless runner passed. Outputs in %", HEADLESS_IR_DIR);
}

main :: () {}
