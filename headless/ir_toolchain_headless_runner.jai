#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import,file "../ir_pipeline/external_toolchain.jai";

HEADLESS_DIR :: ".build/headless_ir_toolchain";

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_file_contains :: (path: string, pattern: string) {
  data, ok := read_entire_file(path);
  if !ok fail("Could not read file: %", path);
  found, _ := contains(data, pattern);
  if !found fail("Expected pattern '%' in %", pattern, path);
}

glsl_stage_name :: (stage: Slang_Stage) -> string {
  if stage == .VERTEX return "vert";
  return "frag";
}

compile_generated_metal :: (path: string) {
  ok := ir_run_command_checked(tprint("xcrun metal %", path),
                            .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", path, "-o", tprint("%.air", path)]);
  if !ok fail("Failed to compile Metal output: %", path);
}

compile_generated_glsl_vulkan :: (path: string, stage: Slang_Stage) {
  ok := ir_run_command_checked(tprint("glslang vulkan %", path),
                            .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", glsl_stage_name(stage), path]);
  if !ok fail("Failed to compile Vulkan GLSL output: %", path);
}

main :: () {
  if !make_directory_if_it_does_not_exist(HEADLESS_DIR, recursive=true) {
    fail("Could not create %", HEADLESS_DIR);
  }

  slang_source_path := tprint("%/simple_pair.slang", HEADLESS_DIR);
  vs_metal := tprint("%/simple_pair.vert.metal", HEADLESS_DIR);
  fs_metal := tprint("%/simple_pair.frag.metal", HEADLESS_DIR);

  vs_vk_gl := tprint("%/simple_pair_vk.vert.glsl", HEADLESS_DIR);
  fs_vk_gl := tprint("%/simple_pair_vk.frag.glsl", HEADLESS_DIR);

  slang_source :: #string END
struct VSIn {
    float2 pos : POSITION;
    uint vid : SV_VertexID;
};

struct VSOut {
    float4 position : SV_Position;
};

struct Params {
    float4 color;
};

[shader("vertex")]
VSOut vsMain(VSIn input)
{
    VSOut o;
    float x = input.pos.x + (float(input.vid) * 0.0);
    o.position = float4(x, input.pos.y, 0.0, 1.0);
    return o;
}

struct PSOut {
    float4 outColor : SV_Target0;
};

[shader("fragment")]
PSOut fsMain(VSOut input, ConstantBuffer<Params> params)
{
    PSOut o;
    o.outColor = params.color;
    return o;
}
END

  if !write_entire_file(slang_source_path, slang_source) {
    fail("Failed to write slang source to %", slang_source_path);
  }

  if !emit_slang_target_source(slang_source_path, "vsMain", .VERTEX, .METAL, vs_metal) fail("Slang failed for vertex metal");
  if !emit_slang_target_source(slang_source_path, "fsMain", .FRAGMENT, .METAL, fs_metal) fail("Slang failed for fragment metal");
  if !emit_slang_target_source(slang_source_path, "vsMain", .VERTEX, .VULKAN_GLSL, vs_vk_gl) fail("Slang failed for vertex vulkan glsl");
  if !emit_slang_target_source(slang_source_path, "fsMain", .FRAGMENT, .VULKAN_GLSL, fs_vk_gl) fail("Slang failed for fragment vulkan glsl");

  #if OS == .MACOS {
    compile_generated_metal(vs_metal);
    compile_generated_metal(fs_metal);
  } else {
    log("Skipping Metal compile checks on %.", OS);
  }

  compile_generated_glsl_vulkan(vs_vk_gl, .VERTEX);
  compile_generated_glsl_vulkan(fs_vk_gl, .FRAGMENT);

  check_file_contains(vs_metal, "vertex");
  check_file_contains(fs_metal, "fragment");
  check_file_contains(vs_vk_gl, "#version 46");

  log("IR headless test passed (Slang direct -> Metal/Vulkan GLSL). Outputs in %", HEADLESS_DIR);
}
