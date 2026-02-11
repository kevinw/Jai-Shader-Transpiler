#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
Process :: #import "Process";

DEBUG_OUTDIR :: ".generated_shaders";

run_all_tests :: () {
  log("Running tests...");
  run_command_checked("Clean legacy GLSL SPIR-V outputs", .["rm", "-f", "frag.spv", "vert.spv", "comp.spv"]);
  run_command_checked("Clean IR Slang output dirs", .["rm", "-rf", ".build/ir_slang", "headless_ir/.build/ir_slang"]);
  run_command_checked("Run headless IR smoke tests", .["bash", "headless_ir/test_ir_headless.sh"]);
  run_command_checked("Run headless IR compute semantics tests", .["bash", "headless_ir/test_ir_compute_semantics.sh"]);
  compile_slang_emitted_metal_shaders();
  
  use_spirv_backend := false;
  for get_command_line_arguments() {
    if it == "-use_spirv_backend" {
      use_spirv_backend = true;
    }
  }
  
  args: [..]string;
  array_add(*args, "jai", "-quiet", "build.jai", "-", "-output_shaders");
  if use_spirv_backend {
    array_add(*args, "-use_spirv_backend");
  }
      
  run_command_checked("Build shaders", args);
  
  debug_path :: (name: string) -> string {
      return tprint("%/%", DEBUG_OUTDIR, name);
  }
  
  if !use_spirv_backend {
    check_file_contains(debug_path("array_support_vertex_shader.glsl"), "vec2 positions[3] = vec2[](");
    check_file_contains(debug_path("array_support_fragment_shader.glsl"), "uniform vec4 u_palette[2];");
    check_file_contains(debug_path("array_support_vertex_shader.metal"), "float2 positions[3] = {");
    check_file_contains(debug_path("compute_write_indices.glsl"), "#version 430 core");
    check_file_contains(debug_path("compute_write_indices.glsl"), "layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;");
    check_file_contains(debug_path("compute_write_indices.glsl"), "gl_GlobalInvocationID");
    check_file_contains(debug_path("tiles_pair_shader.metal"), "vertex VertexShader_Out VertexMain(");
    check_file_contains(debug_path("tiles_pair_shader.metal"), "fragment FragmentShader_Out FragmentMain(");
    check_file_contains(debug_path("tiles_pair_shader.metal"), "float2x2(float2(cos(rot), -sin(rot)), float2(sin(rot), cos(rot)))");
    check_file_not_contains(debug_path("array_support_vertex_shader.glsl"), "<operator_not_supported>");
    check_file_contains(debug_path("tiles_fragment_shader.metal"), "float2x2(float2(cos(rot), -sin(rot)), float2(sin(rot), cos(rot)))");
    check_file_contains(debug_path("array_support_fragment_shader.metal"), "float4 u_palette[2];");
  }
  if use_spirv_backend {
    // SPIR-V-Cross may fold local array literals, so validate indexed uniform usage instead.
    check_file_contains(debug_path("array_support_vertex_shader.metal"), "un.u_offsets.data[2]");
    check_file_contains(debug_path("array_support_vertex_shader.metal"), "un.u_offsets.data[1]");
    check_file_contains(debug_path("array_support_fragment_shader.metal"), "un.u_palette.data[1]");
    check_file_contains(debug_path("tiles_fragment_shader.metal"), "float2x2(");
    check_file_contains(debug_path("tiles_fragment_shader.metal"), "gl_FragCoord");
  }
  check_file_contains(debug_path("tiles_vertex_shader_vk.glsl"), "#version 450");
  check_file_contains_any(debug_path("tiles_vertex_shader_vk.glsl"), .["layout (location=0) in", "layout(location = 0) in"]);
  check_file_contains_any(debug_path("tiles_fragment_shader_vk.glsl"), .["layout (location=0) out", "layout(location = 0) out"]);
  check_file_contains(debug_path("tiles_fragment_shader_vk.glsl"), "layout(set = 0, binding = 0");
  check_file_contains(debug_path("compute_write_indices_vk.glsl"), "std430");
  check_file_contains(debug_path("bindless_nested_vertex_vk.glsl"), "readonly buffer StructuredBuffer");
  check_file_contains(debug_path("bindless_nested_vertex_vk.glsl"), "params_vertex_data");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector2");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector3");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector4");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "<operator_not_supported>");

  for collect_generated_files(".glsl") check_file_not_contains(it, "#string END");
  for collect_generated_files(".metal") check_file_not_contains(it, "#string END");

  compile_generated_metal_shaders();
  compile_generated_glsl_shaders();
  compile_slang_emitted_metal_shaders();
  
  // run example programs with the generated shaders to check they work at runtime (not just compile time).
  run_command_checked("Run GLSL example", .["./glsl_example", "-singleframe", "-test_readback"]);
  run_command_checked("Run CPU example", .["./cpu_example", "-single_frame", "-test_readback"]);
  run_command_checked("Run Vulkan example", .["./vulkan_example", "-single_frame", "-test_readback"]);
  
  #if OS == .MACOS 
    run_command_checked("Run Metal example", .["./metal_example", "-singleframe", "-test_readback"]);

  log("Array shader checks passed. CPU, Metal, GLSL, and Vulkan transpile checks succeeded.");
}

fail :: (message: string, args: .. Any) {
    log_error(message, ..args);
    exit(1);
}

run_command_checked :: (description: string, args: [] string, timeout_ms := -1) {
    command := Process.get_quoted_command_string(args);
    result, output, error, timeout_reached := Process.run_command(..args, timeout_ms=timeout_ms);

    if timeout_reached {
        fail("% timed out. Command: %", description, command);
    }

    if result.type == .FAILED_TO_LAUNCH {
        fail("% failed to launch. Command: %", description, command);
    }

    if result.type != .EXITED || result.exit_code != 0 {
        fail("% failed with exit code %. Command: %", description, result.exit_code, command);
    }
}

check_file_contains :: (name: string, pattern: string) {
    data, ok := read_entire_file(name);
    if !ok {
        fail("Could not read '%'.", name);
    }

    found, _ := contains(data, pattern);
    if !found {
        fail("Expected pattern not found in %: %", name, pattern);
    }
}

check_file_not_contains :: (name: string, pattern: string) {
    data, ok := read_entire_file(name);
    if !ok {
        fail("Could not read '%'.", name);
    }

    found, _ := contains(data, pattern);
    if found {
        fail("Unexpected pattern found in %: %", name, pattern);
    }
}

check_file_contains_any :: (name: string, patterns: [] string) {
    assert(patterns.count > 0);
    data, ok := read_entire_file(name);
    if !ok {
        fail("Could not read '%'.", name);
    }

    for patterns {
        found, _ := contains(data, it);
        if found return;
    }

    fail("Expected at least one pattern in %.", name);
}

collect_generated_files :: (extension: string) -> [..] string {
    Args :: struct {
        extension: string;
        files: *[..] string;
    }

    files: [..] string;
    args: Args;
    args.extension = extension;
    args.files = *files;

    visitor :: (info: *File_Visit_Info, args: *Args) {
        if !ends_with(info.short_name, args.extension) return;
        found_internal, _ := contains(info.short_name, "__get_transpiled_");
        if found_internal return;
        array_add(args.files, copy_string(tprint("%/%", DEBUG_OUTDIR, info.short_name)));
    }

    ok := visit_files(DEBUG_OUTDIR, recursive=false, *args, visitor, visit_files=true, visit_directories=false);
    if !ok {
        fail("Failed while listing generated shader files.");
    }

    return files;
}

collect_files_with_extension_in_dir :: (directory: string, extension: string) -> [..] string {
    Args :: struct {
        directory: string;
        extension: string;
        files: *[..] string;
    }

    files: [..] string;
    args: Args;
    args.directory = directory;
    args.extension = extension;
    args.files = *files;

    visitor :: (info: *File_Visit_Info, args: *Args) {
        if !ends_with(info.short_name, args.extension) return;
        array_add(args.files, copy_string(tprint("%/%", args.directory, info.short_name)));
    }

    ok := visit_files(directory, recursive=false, *args, visitor, visit_files=true, visit_directories=false);
    if !ok {
        fail("Failed while listing files in '%' with extension '%'.", directory, extension);
    }
    return files;
}

glsl_stage_from_filename :: (name: string) -> string {
    found, _ := contains(name, "vertex");
    if found return "vert";
    found, _ = contains(name, "fragment");
    if found return "frag";
    found, _ = contains(name, "compute");
    if found return "comp";

    fail("Unable to infer GLSL stage from filename: %", name);
    return "";
}

compile_generated_glsl_shaders :: () {
    glsl_files := collect_generated_files(".glsl");
    if glsl_files.count == 0 {
        fail("No generated GLSL shader files found (expected output_*.glsl).");
    }

    for glsl_files {
        stage := glsl_stage_from_filename(it);
        is_vulkan_glsl := false;
        found, _ := contains(it, "_vk.glsl");
        if found is_vulkan_glsl = true;
        stem := path_filename(it);
        if ends_with(stem, ".glsl") {
            stem.count -= ".glsl".count;
        }
        spv_path := tprint("%/%.spv", DEBUG_OUTDIR, stem);

        if is_vulkan_glsl {
            run_command_checked(tprint("Compile Vulkan GLSL %", it),
                .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", stage, it, "-o", spv_path]);
        } else {
            run_command_checked(tprint("Compile GLSL %", it),
                .["glslangValidator", "-S", stage, it, "-o", spv_path]);
        }
        assert(spv_path[0] != #char "/");
        run_command_checked(tprint("Delete GLSL SPIR-V output %", spv_path), .["rm", "-f", spv_path]);
    }
}

compile_generated_metal_shaders :: () {
    #if OS != .MACOS {
        log("Skipping Metal compile checks on %.", OS);
        return;
    }

    #if OS == .MACOS {
      metal_files := collect_generated_files(".metal");
      if metal_files.count == 0 {
          fail("No generated Metal shader files found (expected output_*.metal).");
      }
    }

    if !make_directory_if_it_does_not_exist(".build/tests", recursive=true) {
        fail("Could not create .build/tests output directory for Metal compiler artifacts.");
    }

    #if OS == .MACOS {
      for metal_files {
          stem := path_filename(it);
          stem.count -= ".metal".count;
  
          air := tprint(".build/tests/%.air", stem);
          metallib := tprint(".build/tests/%.metallib", stem);
  
          run_command_checked(tprint("Compile Metal %", it),
              .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", it, "-o", air]);
          run_command_checked(tprint("Link Metal library %", it),
              .["xcrun", "-sdk", "macosx", "metallib", air, "-o", metallib]);
      }
    }
}

compile_slang_emitted_metal_shaders :: () {
    #if OS != .MACOS {
        log("Skipping Slang-emitted Metal syntax checks on %.", OS);
        return;
    }

    #if OS == .MACOS {
      roots: [2] string = .[".build/ir_slang", "headless_ir/.build/ir_slang"];
      found_any := false;
      for roots {
          if !file_exists(it) continue;
          metal_files := collect_files_with_extension_in_dir(it, ".metal");
          for metal_files {
              found_any = true;
              run_command_checked(tprint("Syntax-check Slang Metal %", it),
                  .["xcrun", "-sdk", "macosx", "metal", "-fsyntax-only", "-c", it]);
          }
      }
      if !found_any {
          fail("No Slang-emitted Metal files found in .build/ir_slang roots.");
      }
    }
}

main :: () {
  run_all_tests();
}
