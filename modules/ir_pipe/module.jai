// Auto-generated interface module for JDLL 'ir_pipe'

to_spvasm :: (shader: *IR_Shader) -> spvasm: string, ok: bool, diag: IR_Diagnostic #no_context #elsewhere ir_pipe_lib "to_spvasm";
ir_lower_compute_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Compute_Shader, bool, IR_Diagnostic #no_context #elsewhere ir_pipe_lib "ir_lower_compute_from_shader_context";
ir_lower_fragment_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Fragment_Shader, bool, IR_Diagnostic #no_context #elsewhere ir_pipe_lib "ir_lower_fragment_from_shader_context";
ir_lower_vertex_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Vertex_Shader, bool, IR_Diagnostic #no_context #elsewhere ir_pipe_lib "ir_lower_vertex_from_shader_context";
ir_get_diagnostic :: (state: *IR_Lowering_State) -> IR_Diagnostic #no_context #elsewhere ir_pipe_lib "ir_get_diagnostic";
ir_set_diagnostic :: (state: *IR_Lowering_State, message: string, node: *Code_Node = null) #no_context #elsewhere ir_pipe_lib "ir_set_diagnostic";
ir_reset_diagnostic :: (state: *IR_Lowering_State) #no_context #elsewhere ir_pipe_lib "ir_reset_diagnostic";
link_spirv_binaries :: (inputs: [] string, output_spv: string) -> bool #no_context #elsewhere ir_pipe_lib "link_spirv_binaries";
disassemble_spirv_binary :: (input_spv: string, output_spvasm: string) -> bool #no_context #elsewhere ir_pipe_lib "disassemble_spirv_binary";
optimize_spirv_binary :: (input_spv: string, output_spv: string) -> bool #no_context #elsewhere ir_pipe_lib "optimize_spirv_binary";
validate_spirv_binary :: (spv_path: string) -> bool #no_context #elsewhere ir_pipe_lib "validate_spirv_binary";
assemble_spirv_text :: (spvasm_path: string, output_spv: string) -> bool #no_context #elsewhere ir_pipe_lib "assemble_spirv_text";
ir_run_command_checked :: (description: string, args: [] string) -> bool #no_context #elsewhere ir_pipe_lib "ir_run_command_checked";
normalize_shader :: (shader: *IR_Shader) -> ok: bool, diag: IR_Diagnostic #elsewhere ir_pipe_lib "normalize_shader";
emit_spirv_cross_target_source :: (spv_path: string, entry_name: string, stage: IR_Shader_Kind, target: Toolchain_Target, output_path: string, use_metal_argument_buffers := false, source_entry_name := "main") -> bool #no_context #elsewhere ir_pipe_lib "emit_spirv_cross_target_source";
#load "public_structs.jai";

#scope_file
#if OS == .MACOS {
    ir_pipe_lib :: #library,no_static_library "macos/ir_pipe";
} else #if OS == .WINDOWS {
    ir_pipe_lib :: #library,no_static_library "win/ir_pipe";
}
