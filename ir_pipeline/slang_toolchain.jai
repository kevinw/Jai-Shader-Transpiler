#import "Basic";
P :: #import "Process";

Slang_Target :: enum {
  METAL;
  VULKAN_GLSL;
}

Slang_Stage :: enum {
  VERTEX;
  FRAGMENT;
  COMPUTE;
}

SLANG_TIMEOUT_MS :: 15_000;

slang_stage_name :: (stage: Slang_Stage) -> string {
  if stage == .VERTEX return "vertex";
  if stage == .FRAGMENT return "fragment";
  return "compute";
}

ir_run_command_checked :: (description: string, args: [] string) -> bool {
  result, output, error, timeout_reached := P.run_command(..args, timeout_ms=SLANG_TIMEOUT_MS);

  if timeout_reached {
    log_error("% timed out after %ms: %", description, SLANG_TIMEOUT_MS, P.get_quoted_command_string(args));
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

compile_slang_to_spirv :: (source_path: string, entry_name: string, stage: Slang_Stage, output_spv: string) -> bool {
  return ir_run_command_checked(
    tprint("slangc %", entry_name),
    .["slangc", source_path, "-entry", entry_name, "-stage", slang_stage_name(stage), "-target", "spirv", "-o", output_spv]);
}

assemble_spirv_text :: (spvasm_path: string, output_spv: string) -> bool {
  return ir_run_command_checked(
    tprint("spirv-as %", spvasm_path),
    .["spirv-as", spvasm_path, "--target-env", "vulkan1.2", "-o", output_spv]);
}

validate_spirv_binary :: (spv_path: string) -> bool {
  return ir_run_command_checked(
    tprint("spirv-val %", spv_path),
    .["spirv-val", "--target-env", "vulkan1.2", spv_path]);
}

spirv_cross_stage_name :: (stage: Slang_Stage) -> string {
  if stage == .VERTEX return "vert";
  if stage == .FRAGMENT return "frag";
  return "comp";
}

emit_spirv_cross_target_source :: (spv_path: string, entry_name: string, stage: Slang_Stage, target: Slang_Target, output_path: string) -> bool {
  if target == .METAL {
    return ir_run_command_checked(
      tprint("spirv-cross metal %", entry_name),
      .["spirv-cross", spv_path, "--msl", "--msl-version", "30000", "--msl-decoration-binding",
        "--rename-entry-point", "main", entry_name, spirv_cross_stage_name(stage),
        "--output", output_path]);
  }

  if target == .VULKAN_GLSL {
    return ir_run_command_checked(
      tprint("spirv-cross glsl %", entry_name),
      .["spirv-cross", spv_path, "--vulkan-semantics", "--version", "450", "--output", output_path]);
  }

  log_error("Unsupported SPIR-V target requested in IR pipeline: %", target);
  return false;
}

emit_slang_target_source :: (source_path: string, entry_name: string, stage: Slang_Stage, target: Slang_Target, output_path: string, emit_line_directives := false) -> bool {
  line_mode := ifx emit_line_directives then "default" else "none";
  if target == .METAL {
    return ir_run_command_checked(
      tprint("slangc metal %", entry_name),
      .["slangc", source_path, "-entry", entry_name, "-stage", slang_stage_name(stage), "-target", "metal", "-line-directive-mode", line_mode, "-o", output_path]);
  }

  if target == .VULKAN_GLSL {
    return ir_run_command_checked(
      tprint("slangc glsl %", entry_name),
      .["slangc", source_path, "-entry", entry_name, "-stage", slang_stage_name(stage), "-target", "glsl", "-profile", "glsl_450", "-line-directive-mode", line_mode, "-o", output_path]);
  }

  log_error("Unsupported Slang target requested in new IR pipeline: %", target);
  return false;
}

emit_slang_module_target_source :: (source_path: string, target: Slang_Target, output_path: string, emit_line_directives := false) -> bool {
  line_mode := ifx emit_line_directives then "default" else "none";
  if target == .METAL {
    return ir_run_command_checked(
      "slangc metal module",
      .["slangc", source_path, "-target", "metal", "-line-directive-mode", line_mode, "-o", output_path]);
  }

  if target == .VULKAN_GLSL {
    return ir_run_command_checked(
      "slangc glsl module",
      .["slangc", source_path, "-target", "glsl", "-profile", "glsl_450", "-line-directive-mode", line_mode, "-o", output_path]);
  }

  log_error("Unsupported Slang module target requested in IR pipeline: %", target);
  return false;
}
