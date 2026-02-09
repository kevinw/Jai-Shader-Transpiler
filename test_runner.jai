#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
Process :: #import "Process";

DEBUG_OUTDIR :: ".generated_shaders";

run_all_tests :: () {
  log("Running tests...");
  run_command_checked("Build shaders", .["jai", "-quiet", "build.jai", "-", "-output_shaders"]);
  
  debug_path :: (name: string) -> string {
      return tprint("%/%", DEBUG_OUTDIR, name);
  }
  
  check_file_contains(debug_path("array_support_vertex_shader.glsl"), "vec2 positions[3] = vec2[](");
  check_file_contains(debug_path("array_support_vertex_shader.metal"), "float2 positions[3] = {");
  check_file_contains(debug_path("array_support_fragment_shader.glsl"), "uniform vec4 u_palette[2];");
  check_file_contains(debug_path("array_support_fragment_shader.metal"), "float4 u_palette[2];");
  check_file_contains(debug_path("compute_write_indices.glsl"), "#version 430 core");
  check_file_contains(debug_path("compute_write_indices.glsl"), "layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;");
  check_file_contains(debug_path("compute_write_indices.glsl"), "gl_GlobalInvocationID");
  check_file_contains(debug_path("tiles_vertex_shader_vk.glsl"), "#version 450 core");
  check_file_contains(debug_path("tiles_vertex_shader_vk.glsl"), "layout (location=0) in");
  check_file_contains(debug_path("tiles_fragment_shader_vk.glsl"), "layout (location=0) out");
  check_file_contains(debug_path("tiles_fragment_shader_vk.glsl"), "layout(set = 0, binding = 0) uniform");
  check_file_contains(debug_path("compute_write_indices_vk.glsl"), "layout(std430, set = 0, binding = 0) buffer");
  check_file_contains(debug_path("tiles_fragment_shader.metal"), "float2x2(float2(cos(rot), -sin(rot)), float2(sin(rot), cos(rot)))");

  check_file_not_contains(debug_path("array_support_vertex_shader.glsl"), "<operator_not_supported>");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "<operator_not_supported>");

  for collect_generated_files(".glsl") check_file_not_contains(it, "#string END");
  for collect_generated_files(".metal") check_file_not_contains(it, "#string END");

  compile_generated_metal_shaders();
  compile_generated_glsl_shaders();
  
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
        array_add(args.files, copy_string(tprint("%/%", DEBUG_OUTDIR, info.short_name)));
    }

    ok := visit_files(DEBUG_OUTDIR, recursive=false, *args, visitor, visit_files=true, visit_directories=false);
    if !ok {
        fail("Failed while listing generated shader files.");
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
        run_command_checked(tprint("Compile GLSL %", it), .["glslangValidator", "-S", stage, it]);
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

main :: () {
  run_all_tests();
}
