#import "Basic";
#import "Math";
#import "File";
Process :: #import "Process";

#import,file "../module.jai"; // #import "Jai-Shader-Transpiler" in your code.

#load "vulkan_shaders.jai";

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
        if output.count != 0 log_error("%", output);
        if error.count != 0 log_error("%", error);
        fail("% failed with exit code %. Command: %", description, result.exit_code, command);
    }
}

write_shader_source :: (dir: string, basename: string, extension: string, source: string) -> string {
    path := tprint("%/%.%", dir, basename, extension);
    ok := write_entire_file(path, source);
    if !ok fail("Failed to write shader source file %", path);
    return path;
}

compile_glsl_to_spirv :: (source_path: string, stage: string) {
    output_path := tprint("%.spv", source_path);
    run_command_checked(tprint("Compile %", source_path),
        .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", stage, source_path, "-o", output_path]);
}

main :: () {
    _ := tiles_vertex_shader_vk(.{}, .{});
    _ = tiles_fragment_shader_vk(.{}, .{});
    _ = tiles_vertex_shader_vk_string;
    _ = tiles_fragment_shader_vk_string;

    _ = compute_write_indices_vk;
    _ = compute_write_indices_vk_string;

    output_dir :: ".build/vulkan_example";
    if !make_directory_if_it_does_not_exist(output_dir, recursive=true) {
        fail("Failed to create output directory %", output_dir);
    }

    vertex_path := write_shader_source(output_dir, "tiles_vertex_shader_vk", "vert.glsl", tiles_vertex_shader_vk_string);
    fragment_path := write_shader_source(output_dir, "tiles_fragment_shader_vk", "frag.glsl", tiles_fragment_shader_vk_string);
    compute_path := write_shader_source(output_dir, "compute_write_indices_vk", "comp.glsl", compute_write_indices_vk_string);

    compile_glsl_to_spirv(vertex_path, "vert");
    compile_glsl_to_spirv(fragment_path, "frag");
    compile_glsl_to_spirv(compute_path, "comp");

    log("Vulkan sample succeeded: transpiled vertex/fragment/compute GLSL compiled to SPIR-V.");
}
