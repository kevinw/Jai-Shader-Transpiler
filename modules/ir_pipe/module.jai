// Auto-generated JDLL interface module 'ir_pipe'

ir_get_diagnostic :: (state: *IR_Lowering_State) -> IR_Diagnostic #foreign ir_pipe_lib "_jdll_ir_get_diagnostic";
ir_set_diagnostic :: (state: *IR_Lowering_State, message: string, node: *Code_Node = null) #c_call #foreign ir_pipe_lib "_jdll_ir_set_diagnostic";
ir_reset_diagnostic :: (state: *IR_Lowering_State) #foreign ir_pipe_lib "_jdll_ir_reset_diagnostic";
ir_uses_pointer_abi_local :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool #foreign ir_pipe_lib "_jdll_ir_uses_pointer_abi_local";
ir_struct_has_pointer_fields_recursive_local :: (extra_structs: [] IR_Struct, name: string) -> bool #foreign ir_pipe_lib "_jdll_ir_struct_has_pointer_fields_recursive_local";
spv_memory_model_from_text :: (spvasm: string) -> string #foreign ir_pipe_lib "_jdll_spv_memory_model_from_text";
ir_merge_metal_pair_sources :: (vertex_source: string, fragment_source: string) -> string #foreign ir_pipe_lib "_jdll_ir_merge_metal_pair_sources";
ir_metal_split_top_level_decls :: (source: string, out_preamble: *string, out_decls: *[..] string) #foreign ir_pipe_lib "_jdll_ir_metal_split_top_level_decls";
shader_name_from_call_arg :: (arg: *Code_Node) -> string #foreign ir_pipe_lib "_jdll_shader_name_from_call_arg";
link_spirv_binaries :: (inputs: [] string, output_spv: string) -> bool #c_call #foreign ir_pipe_lib;
disassemble_spirv_binary :: (input_spv: string, output_spvasm: string) -> bool #c_call #foreign ir_pipe_lib;
optimize_spirv_binary :: (input_spv: string, output_spv: string) -> bool #c_call #foreign ir_pipe_lib;
validate_spirv_binary :: (spv_path: string) -> bool #c_call #foreign ir_pipe_lib;
assemble_spirv_text :: (spvasm_path: string, output_spv: string) -> bool #c_call #foreign ir_pipe_lib;
ir_run_command_checked :: (description: string, args: [] string) -> bool #c_call #foreign ir_pipe_lib;
normalize_shader :: (shader: *IR_Shader) #foreign ir_pipe_lib "_jdll_normalize_shader";
emit_spirv_cross_target_source :: (spv_path: string, entry_name: string, stage: IR_Shader_Kind, target: Toolchain_Target, output_path: string, use_metal_argument_buffers := false, source_entry_name := "main") -> bool #c_call #foreign ir_pipe_lib;
to_spvasm :: (shader: *IR_Shader) -> IR_Result(string) #foreign ir_pipe_lib "_jdll_to_spvasm";
ir_lower_compute_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Compute_Shader) #foreign ir_pipe_lib "_jdll_ir_lower_compute_from_shader_context";
ir_lower_fragment_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Fragment_Shader) #foreign ir_pipe_lib "_jdll_ir_lower_fragment_from_shader_context";
ir_lower_vertex_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Vertex_Shader) #foreign ir_pipe_lib "_jdll_ir_lower_vertex_from_shader_context";
    
#load "../../ir_pipeline/public_structs.jai";


#scope_file
#if OS == .MACOS   ir_pipe_lib :: #library,no_static_library "macos/ir_pipe";
#if OS == .WINDOWS ir_pipe_lib :: #library,no_static_library "windows/ir_pipe";
