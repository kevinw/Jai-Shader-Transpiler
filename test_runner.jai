#import "Basic";
String :: #import "String";
#import "File";
#import "File_Utilities";
Process :: #import "Process";
using,only(getenv) POSIX :: #import "POSIX";

DEBUG_OUTDIR :: ".generated_shaders";
TIMINGS_ENABLED := false;

time_scope :: (enabled: bool, label: string) #expand {
  __jsl_timing_enabled := enabled;
  __jsl_timing_start := current_time_monotonic();
  `defer {
    if __jsl_timing_enabled {
      __jsl_timing_elapsed := to_float64_seconds(current_time_monotonic() - __jsl_timing_start);
      log("[timing] %: %s", label, __jsl_timing_elapsed);
    }
  }
}

run_all_tests :: () {
  log("Running tests...");
  for get_command_line_arguments() {
    if it == "-timings" TIMINGS_ENABLED = true;
  }
  {
    time_scope(TIMINGS_ENABLED, "run_all_tests total");

    {
      time_scope(TIMINGS_ENABLED, "Cleanup generated outputs");
      run_command_checked("Clean legacy GLSL SPIR-V outputs", .["rm", "-f", "frag.spv", "vert.spv", "comp.spv"]);
      run_command_checked("Clean IR intermediate output dirs", .["rm", "-rf", ".build/ir_intermediate", "headless_ir/.build/ir_intermediate"]);
    }

    {
      time_scope(TIMINGS_ENABLED, "Headless IR smoke tests");
      run_command_checked("Run headless IR smoke tests", .["bash", "headless_ir/test_ir_headless.sh"]);
    }

    {
      time_scope(TIMINGS_ENABLED, "Headless IR compute semantics");
      args: [..] string;
      array_add(*args, "bash", "headless_ir/test_ir_compute_semantics.sh");
      if TIMINGS_ENABLED array_add(*args, "-timings");
      run_command_checked("Run headless IR compute semantics tests", args);
    }
    {
      time_scope(TIMINGS_ENABLED, "Headless IR graphics semantics");
      run_command_checked("Run headless IR graphics semantics tests", .["bash", "headless_ir/test_ir_graphics_semantics.sh"]);
    }

    {
      time_scope(TIMINGS_ENABLED, "Syntax-check generated Metal");
      syntax_check_generated_metal_shaders();
    }
  
  debug_path :: (name: string) -> string { return tprint("%/%", DEBUG_OUTDIR, name); }
  
  // SPIR-V-Cross may fold local array literals, so validate indexed uniform usage instead.
  check_file_contains_any(debug_path("array_support_vertex_shader.metal"), .["un.u_offsets[2u]", "(*spvDescriptorSet0.un).u_offsets[2u]", "un._m0[2u]"]);
  check_file_contains_any(debug_path("array_support_vertex_shader.metal"), .["un.u_offsets[1u]", "(*spvDescriptorSet0.un).u_offsets[1u]", "un._m0[1u]"]);
  check_file_contains_any(debug_path("array_support_fragment_shader.metal"), .["un.u_palette[1u]", "(*spvDescriptorSet0.un).u_palette[1u]", "un._m0[1u]"]);
  check_file_contains(debug_path("tiles_fragment_shader.metal"), "float2x2(");
  check_file_contains(debug_path("tiles_fragment_shader.metal"), "gl_FragCoord");
  check_file_contains(debug_path("tiles_vertex_shader_vk.glsl"), "#version 450");
  check_file_contains_any(debug_path("tiles_vertex_shader_vk.glsl"), .["layout (location=0) in", "layout(location = 0) in"]);
  check_file_contains_any(debug_path("tiles_fragment_shader_vk.glsl"), .["layout (location=0) out", "layout(location = 0) out"]);
  check_file_contains(debug_path("tiles_fragment_shader_vk.glsl"), "layout(set = 0, binding = 0");
  check_file_contains(debug_path("compute_write_indices_vk.glsl"), "std430");
  check_file_contains(debug_path("bindless_nested_vertex_vk.glsl"), "binding = 0, std430) buffer");
  check_file_contains(debug_path("bindless_nested_vertex_vk.glsl"), "params_vertex_data");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector2");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector3");
  check_file_not_contains(debug_path("array_support_vertex_shader.metal"), "struct Vector4");
  for collect_generated_files(".glsl") check_file_not_contains(it, "#string END");
  for collect_generated_files(".metal") check_file_not_contains(it, "#string END");

    {
      time_scope(TIMINGS_ENABLED, "Compile generated Metal shaders");
      compile_generated_metal_shaders();
    }
    {
      time_scope(TIMINGS_ENABLED, "Compile generated GLSL shaders");
      compile_generated_glsl_shaders();
    }
  
    // run example programs with the generated shaders to check they work at runtime (not just compile time).
    {
      time_scope(TIMINGS_ENABLED, "Run GLSL example");
      run_command_checked("Run GLSL example", .["./glsl_example", "-singleframe", "-test_readback"]);
    }
    {
      time_scope(TIMINGS_ENABLED, "Run CPU example");
      run_command_checked("Run CPU example", .["./cpu_example", "-single_frame", "-test_readback"]);
    }
    {
      time_scope(TIMINGS_ENABLED, "Run Vulkan example");
      run_command_checked("Run Vulkan example", .["./vulkan_example", "-single_frame", "-test_readback"]);
    }
    
    #if OS == .MACOS {
      {
        time_scope(TIMINGS_ENABLED, "Run Metal example");
        run_command_checked("Run Metal example", .["./metal_example", "-singleframe", "-test_readback"]);
      }
    }
  }
  log("All Jai-Shader-Transpiler tests passed.");
}

fail :: (message: string, args: .. Any) {
    log_error(message, ..args);
    exit(1);
}

run_command_checked :: (description: string, args: [] string, timeout_ms := -1) {
    command := Process.get_quoted_command_string(args);
    result, output, error, timeout_reached := Process.run_command(..args, timeout_ms=timeout_ms);

    if timeout_reached  fail("% timed out. Command: %", description, command);
    if result.type == .FAILED_TO_LAUNCH  fail("% failed to launch. Command: %", description, command);
    if result.type != .EXITED || result.exit_code != 0  fail("% failed with exit code %. Command: %", description, result.exit_code, command);
}

default_parallel_jobs :: (file_count: s64) -> s64 {
    jobs := 4;
    if file_count <= 1 jobs = 1;
    if jobs > file_count jobs = file_count;
    return max(1, jobs);
}

env_var_is_truthy :: (name: string) -> bool {
    value_c := getenv(temp_c_string(name));
    if !value_c return false;
    value := to_string(value_c, c_style_strlen(value_c));
    if value.count == 0 return false;

    parsed, ok, _ := String.string_to_int(value);
    if ok return cast(s64) parsed != 0;

    if value == "false" return false;
    if value == "FALSE" return false;
    if value == "off" return false;
    if value == "OFF" return false;
    if value == "no" return false;
    if value == "NO" return false;
    return true;
}

run_parallel_script_over_files :: (description: string, files: [] string, jobs: s64, per_file_script: string) {
    if files.count == 0 return;
    if env_var_is_truthy("JST_SERIAL_TOOL_CHECKS") jobs = 1;
    jobs = max(1, jobs);
    if jobs > files.count jobs = files.count;

    if jobs == 1 {
        for files {
            run_command_checked(tprint("% %", description, it),
                .["bash", "-lc", per_file_script, "--", it]);
        }
        return;
    }

    xargs_script :: #string END
jobs="$1"
script="$2"
shift 2
printf '%s\0' "$@" | xargs -0 -P "$jobs" -I{} bash -lc "$script" -- "{}"
END;

    args: [..] string;
    array_add(*args, "bash", "-lc", xargs_script, "--", tprint("%", jobs), per_file_script);
    for files array_add(*args, it);
    run_command_checked(tprint("% (% files, jobs=%)", description, files.count, jobs), args);
}

check_file_contains :: (name: string, pattern: string) {
    data, ok := read_entire_file(name);
    if !ok  fail("Could not read '%'.", name);

    found, _ := String.contains(data, pattern);
    if !found  fail("Expected pattern not found in %: %", name, pattern);
}

check_file_not_contains :: (name: string, pattern: string) {
    data, ok := read_entire_file(name);
    if !ok  fail("Could not read '%'.", name);

    found, _ := String.contains(data, pattern);
    if found  fail("Unexpected pattern found in %: %", name, pattern);
}

check_file_contains_any :: (name: string, patterns: [] string) {
    assert(patterns.count > 0);
    data, ok := read_entire_file(name);
    if !ok  fail("Could not read '%'.", name);

    for patterns {
        found, _ := String.contains(data, it);
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
        if !String.ends_with(info.short_name, args.extension) return;
        found_internal_single, _ := String.contains(info.short_name, "transpiled_single_");
        found_internal_pair, _ := String.contains(info.short_name, "transpiled_pair_");
        found_internal := found_internal_single || found_internal_pair;
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
        if !String.ends_with(info.short_name, args.extension) return;
        array_add(args.files, copy_string(tprint("%/%", args.directory, info.short_name)));
    }

    ok := visit_files(directory, recursive=false, *args, visitor, visit_files=true, visit_directories=false);
    if !ok {
        fail("Failed while listing files in '%' with extension '%'.", directory, extension);
    }
    return files;
}

glsl_stage_from_filename :: (name: string) -> string {
    found, _ := String.contains(name, "vertex");
    if found return "vert";
    found, _ = String.contains(name, "fragment");
    if found return "frag";
    found, _ = String.contains(name, "compute");
    if found return "comp";

    fail("Unable to infer GLSL stage from filename: %", name);
    return "";
}

compile_generated_glsl_shaders :: () {
    glsl_files := collect_generated_files(".glsl");
    if glsl_files.count == 0 {
        fail("No generated GLSL shader files found (expected output_*.glsl).");
    }
    jobs := default_parallel_jobs(glsl_files.count);
    glsl_compile_script :: #string END
file="$1"
stage=""
case "$file" in
  *vertex*) stage="vert" ;;
  *fragment*) stage="frag" ;;
  *compute*) stage="comp" ;;
  *)
    echo "Unable to infer GLSL stage from filename: $file" >&2
    exit 2
    ;;
esac
stem="$(basename "$file" .glsl)"
spv_path=".generated_shaders/${stem}.spv"
if [[ "$file" == *_vk.glsl ]]; then
  glslangValidator -V --target-env vulkan1.2 -S "$stage" "$file" -o "$spv_path"
else
  glslangValidator -S "$stage" "$file" -o "$spv_path"
fi
rm -f "$spv_path"
END;
    run_parallel_script_over_files("Compile generated GLSL shaders", glsl_files, jobs, glsl_compile_script);
}

compile_generated_metal_shaders :: () {
    #if OS != .MACOS {
        log("Skipping Metal compile checks on %.", OS);
        return;
    }

    #if OS == .MACOS {
      metal_files := collect_generated_files(".metal");
      if metal_files.count == 0 fail("No generated Metal shader files found (expected output_*.metal).");
    }

    if !make_directory_if_it_does_not_exist(".build/tests", recursive=true) {
        fail("Could not create .build/tests output directory for Metal compiler artifacts.");
    }

    #if OS == .MACOS {
      jobs := default_parallel_jobs(metal_files.count);
      metal_compile_script :: #string END
file="$1"
stem="$(basename "$file" .metal)"
air=".build/tests/${stem}.air"
metallib=".build/tests/${stem}.metallib"
xcrun -sdk macosx metal -std=metal3.0 -c "$file" -o "$air"
xcrun -sdk macosx metallib "$air" -o "$metallib"
END;
      run_parallel_script_over_files("Compile generated Metal shaders", metal_files, jobs, metal_compile_script);
    }
}

syntax_check_generated_metal_shaders :: () {
    #if OS != .MACOS {
        log("Skipping generated Metal syntax checks on %.", OS);
        return;
    }

    #if OS == .MACOS {
      roots: [2] string = .[".build/ir_intermediate", "headless_ir/.build/ir_intermediate"];
      all_metal_files: [..] string;
      for roots {
          if !file_exists(it) continue;
          metal_files := collect_files_with_extension_in_dir(it, ".metal");
          for metal_files array_add(*all_metal_files, it);
      }
      if all_metal_files.count == 0 {
          fail("No generated Metal files found in .build/ir_intermediate roots.");
      }

      syntax_jobs := 4;
      if all_metal_files.count <= 1 syntax_jobs = 1;
      syntax_check_generated_metal_shaders_parallel(all_metal_files, syntax_jobs);
    }
}

syntax_check_generated_metal_shaders_parallel :: (metal_files: []string, jobs: s64) {
    if metal_files.count == 0 return;
    script :: #string END
file="$1"
xcrun -sdk macosx metal -fsyntax-only -c "$file"
END;
    run_parallel_script_over_files("Syntax-check generated Metal", metal_files, jobs, script);
}

main :: () {
  run_all_tests();
}
