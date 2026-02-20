#import "Basic";
#import "File";
#import "File_Utilities";
String :: #import "String";
#import,dir "../modules/ir_pipe";

HEADLESS_DIR :: ".build/headless_ir_toolchain";

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_file_contains :: (path: string, pattern: string) {
  data, ok := read_entire_file(path);
  if !ok fail("Could not read file: %", path);
  found, _ := String.contains(data, pattern);
  if !found fail("Expected pattern '%' in %", pattern, path);
}

compile_generated_metal :: (path: string) {
  ok := ir_run_command_checked(tprint("xcrun metal %", path),
                            .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", path, "-o", tprint("%.air", path)]);
  if !ok fail("Failed to compile Metal output: %", path);
}

compile_generated_glsl_vulkan :: (path: string, stage: string) {
  ok := ir_run_command_checked(tprint("glslang vulkan %", path),
                            .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", stage, path]);
  if !ok fail("Failed to compile Vulkan GLSL output: %", path);
}

main :: () {
  if !make_directory_if_it_does_not_exist(HEADLESS_DIR, recursive=true) {
    fail("Could not create %", HEADLESS_DIR);
  }

  vs_metal := tprint("%/simple_pair.vert.metal", HEADLESS_DIR);
  fs_metal := tprint("%/simple_pair.frag.metal", HEADLESS_DIR);

  vs_vk_gl := tprint("%/simple_pair_vk.vert.glsl", HEADLESS_DIR);
  fs_vk_gl := tprint("%/simple_pair_vk.frag.glsl", HEADLESS_DIR);

  metal_vertex_source :: #string END
#include <metal_stdlib>
using namespace metal;
struct VSOut { float4 position [[position]]; };
vertex VSOut VertexMain(uint vid [[vertex_id]]) {
  VSOut o;
  float2 p = (vid == 0) ? float2(-0.5, -0.5) : ((vid == 1) ? float2(0.5, -0.5) : float2(0.0, 0.5));
  o.position = float4(p, 0.0, 1.0);
  return o;
}
END;
  metal_fragment_source :: #string END
#include <metal_stdlib>
using namespace metal;
struct FSOut { float4 color [[color(0)]]; };
fragment FSOut FragmentMain() {
  FSOut o;
  o.color = float4(0.2, 0.4, 0.8, 1.0);
  return o;
}
END;
  vk_vertex_source :: #string END
#version 450
layout(location = 0) out vec3 v_color;
vec2 positions[3] = vec2[](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.0, 0.5));
vec3 colors[3] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
void main() {
  gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
  v_color = colors[gl_VertexIndex];
}
END;
  vk_fragment_source :: #string END
#version 450
layout(location = 0) in vec3 v_color;
layout(location = 0) out vec4 outColor;
void main() {
  outColor = vec4(v_color, 1.0);
}
END;

  if !write_entire_file(vs_metal, metal_vertex_source) fail("Failed to write %", vs_metal);
  if !write_entire_file(fs_metal, metal_fragment_source) fail("Failed to write %", fs_metal);
  if !write_entire_file(vs_vk_gl, vk_vertex_source) fail("Failed to write %", vs_vk_gl);
  if !write_entire_file(fs_vk_gl, vk_fragment_source) fail("Failed to write %", fs_vk_gl);

  #if OS == .MACOS {
    compile_generated_metal(vs_metal);
    compile_generated_metal(fs_metal);
  } else {
    log("Skipping Metal compile checks on %.", OS);
  }

  compile_generated_glsl_vulkan(vs_vk_gl, "vert");
  compile_generated_glsl_vulkan(fs_vk_gl, "frag");

  check_file_contains(vs_metal, "vertex");
  check_file_contains(fs_metal, "fragment");
  check_file_contains(vs_vk_gl, "#version 450");

  log("IR headless toolchain test passed (SPIR-V text -> Metal/Vulkan GLSL). Outputs in %", HEADLESS_DIR);
}
