// Functions for running external shader compilation tools

#program_export
ir_run_command_checked :: (description: string, args: [] string) -> bool #c_call {
    push_context,defer_pop;
  result, output, error, timeout_reached := P.run_command(..args, timeout_ms=EXTERNAL_TOOL_TIMEOUT_MS);

  if timeout_reached {
    log_error("% timed out after %ms: %", description, EXTERNAL_TOOL_TIMEOUT_MS, P.get_quoted_command_string(args));
    return false;
  }

  if result.type == .FAILED_TO_LAUNCH {
    log_error("% failed to launch: %", description, P.get_quoted_command_string(args));
    return false;
  }

  if result.type != .EXITED || result.exit_code != 0 {
    if output.count != 0 log("%", output);
    if error.count != 0 log_error("%", error);
    log_error("% failed with exit code %: %", description, result.exit_code, P.get_quoted_command_string(args));
    return false;
  }

  return true;
}

#program_export
assemble_spirv_text :: (spvasm_path: string, output_spv: string) -> bool #c_call {
  push_context,defer_pop;
  return ir_run_command_checked(
    tprint("spirv-as %", spvasm_path),
    .["spirv-as", spvasm_path, "--target-env", "vulkan1.2", "-o", output_spv]);
}

#program_export
validate_spirv_binary :: (spv_path: string) -> bool #c_call {
    push_context,defer_pop;
  return ir_run_command_checked(
    tprint("spirv-val %", spv_path),
    .["spirv-val", "--target-env", "vulkan1.2", spv_path]);
}

#program_export
optimize_spirv_binary :: (input_spv: string, output_spv: string) -> bool #c_call {
    push_context,defer_pop;
  return ir_run_command_checked(
    tprint("spirv-opt %", input_spv),
    .["spirv-opt", "-O", input_spv, "-o", output_spv]);
}

#program_export
disassemble_spirv_binary :: (input_spv: string, output_spvasm: string) -> bool #c_call {
    push_context,defer_pop;
  return ir_run_command_checked(
    tprint("spirv-dis %", input_spv),
    .["spirv-dis", input_spv, "-o", output_spvasm]);
}

#program_export
link_spirv_binaries :: (inputs: [] string, output_spv: string) -> bool #c_call {
    push_context,defer_pop;
  if inputs.count == 0 {
    log_error("SPIR-V link requires at least one input.");
    return false;
  }
  args: [..] string;
  args.allocator = temp;
  array_add(*args, "spirv-link");
  for inputs array_add(*args, it);
  array_add(*args, "-o", output_spv);
  return ir_run_command_checked(
    tprint("spirv-link % inputs", inputs.count),
    args);
}

#program_export
emit_spirv_cross_target_source :: (spv_path: string, entry_name: string, stage: IR_Shader_Kind, target: Toolchain_Target, output_path: string, use_metal_argument_buffers := false, source_entry_name := "main") -> bool #c_call {
    push_context,defer_pop;
  if target == .METAL {
    if use_metal_argument_buffers && (stage == .Vertex || stage == .Fragment) {
      return ir_run_command_checked(
        tprint("spirv-cross metal %", entry_name),
        .["spirv-cross", spv_path, "--msl", "--msl-version", "30000", "--entry", source_entry_name, "--stage", spirv_cross_stage_name(stage), "--msl-argument-buffers", "--msl-force-active-argument-buffer-resources", "--msl-decoration-binding",
          "--rename-entry-point", source_entry_name, entry_name, spirv_cross_stage_name(stage),
          "--output", output_path]);
    }
    return ir_run_command_checked(
      tprint("spirv-cross metal %", entry_name),
      .["spirv-cross", spv_path, "--msl", "--msl-version", "30000", "--entry", source_entry_name, "--stage", spirv_cross_stage_name(stage), "--msl-decoration-binding",
        "--rename-entry-point", source_entry_name, entry_name, spirv_cross_stage_name(stage),
        "--output", output_path]);
  }

  if target == .VULKAN_GLSL {
    return ir_run_command_checked(
      tprint("spirv-cross glsl %", entry_name),
      .["spirv-cross", spv_path, "--entry", source_entry_name, "--stage", spirv_cross_stage_name(stage), "--vulkan-semantics", "--version", "450", "--output", output_path]);
  }

  log_error("Unsupported SPIR-V target requested in IR pipeline: %", target);
  return false;
}

#scope_file

spirv_cross_stage_name :: (stage: IR_Shader_Kind) -> string {
    if #complete stage == {
        case .Vertex;   return "vert";
        case .Fragment; return "frag";
        case .Compute;  return "comp";
    }
    return "";
}

#import "Basic";
P :: #import "Process";
EXTERNAL_TOOL_TIMEOUT_MS :: 15_000;
