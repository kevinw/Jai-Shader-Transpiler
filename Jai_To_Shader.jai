//
// Metaprogram plugin for converting Jai funcs marked with @vertex_shader @fragment_shader or @compute_shader to shaders.
// 
// Usage:
// 
// metal_bytes := get_transpiled(.METAL, pbr_vertex_main, pbr_fragment_main);
// 

VERBOSE      :: false;
USE_SPIRV_OPT :: true;
IR_INTERMEDIATE_DIR :: ".build/ir_intermediate";
DEBUG_OUTDIR :: ".generated_shaders";
MY_MODULE_NAME :: "Jai-Shader-Transpiler";

Transpiled_Target :: enum {
  METAL;
  HLSL;
  OPENGL_GLSL;
  VULKAN_GLSL;
}

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = convert_procs; // the Compiler message handler
    before_intercept = _before_intercept;
    add_source = _add_source;
    
    // options
    output_shaders: bool;
    shader_entry_ids_filter: string;
    
    // internal
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      manifest_entries: [..] Shader_Reload_Manifest_Entry;
      did_emit_lookup_overloads: bool;
      did_log_ir_pipeline: bool;
      did_log_ir_limitations: bool;
      did_add_setup_source: bool;
    }
}
Transpiled_Lookup_Entry :: struct {
  target_name: string;
  primary_name: string;
  secondary_name: string;
  symbol_name: string;
}

get_plugin :: () -> *Jai_To_Shader_Plugin {
  using p := New(Jai_To_Shader_Plugin);
  for get_build_options().compile_time_command_line {
    if it == "-timings" {
        // 
    } else if it == "-output_shaders" {
      output_shaders = true;
    } else if begins_with(it, "-shader_entry_ids=") {
      shader_entry_ids_filter = trim_ascii_whitespace(string.{ it.count - 18, it.data + 18});
    }
  }

  return p;
}

get_transpiled_requests_seen: Table(string, bool);

expression_to_source_string :: (node: *Code_Node) -> string {
  sb: String_Builder;
  PP.print_expression(*sb, node);
  return builder_to_string(*sb);
}

transpiled_target_from_expr_string :: (expr: string) -> (single_note: string, pair_note: string, supports_pair: bool, is_metal: bool, ok: bool) {
  if expr == {
    case ".METAL";       return "shader_to_metal",  "shader_pair_to_metal",  true,  true,  true;
    case ".HLSL";        return "shader_to_hlsl",   "",                      false, false, true;
    case ".OPENGL_GLSL"; return "shader_to_glsl",   "shader_pair_to_glsl",   true,  false, true;
    case ".VULKAN_GLSL"; return "shader_to_vulkan", "shader_pair_to_vulkan", true,  false, true;
  }
  return "", "", false, false, false;
}

sanitize_identifier_component :: (in: string) -> string {
  out := copy_string(in);
  for out {
    if it == {
      case #char "."; #through;
      case #char " "; #through;
      case #char "("; #through;
      case #char ")"; #through;
      case #char ",";
        out[it_index] = "_";
    }
  }
  return out;
}

ensure_get_transpiled_request_registered :: (key: string, source: string) #compile_time {
  found, _ := table_find(*get_transpiled_requests_seen, key);
  if found return;
  table_add(*get_transpiled_requests_seen, key, true);
  add_build_string(source, get_current_workspace());
}

get_transpiled_result_expr_from_call :: (call: Code, loc: Source_Code_Location) -> string #compile_time {
  root := compiler_get_nodes(call);
  if root.kind != .PROCEDURE_CALL {
    compiler_report("Jai Shader Transpiler: get_transpiled must be called directly (e.g. get_transpiled(.METAL, vertex_fn, fragment_fn)).", loc=loc);
    return "";
  }

  pc := cast(*Code_Procedure_Call) root;
  if pc.arguments_unsorted.count != 2 && pc.arguments_unsorted.count != 3 {
    compiler_report("Jai Shader Transpiler: get_transpiled expects 2 args (target, stage_fn) or 3 args (target, vertex_fn, fragment_fn).", loc=loc);
    return "";
  }

  target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
  target_ident := sanitize_identifier_component(target_expr);
  single_note, pair_note, supports_pair, _, target_ok := transpiled_target_from_expr_string(target_expr);
  if !target_ok {
    compiler_report("Jai Shader Transpiler: First argument to get_transpiled must be .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.", loc=loc);
    return "";
  }

  shader_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
  if !shader_name {
    compiler_report("Jai Shader Transpiler: get_transpiled shader arguments must be procedure identifiers.", loc=loc);
    return "";
  }

  if pc.arguments_unsorted.count == 2 {
    request_name := tprint("transpiled_single_%_%", target_ident, shader_name);
    to_lower_in_place(request_name);
    key := tprint("single|%|%", single_note, shader_name);
    request_source := tprint("% :: %; @%\n", request_name, shader_name, single_note);
    ensure_get_transpiled_request_registered(key, request_source);
    return tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", target_expr, shader_name);
  }

  if !supports_pair {
    compiler_report("Jai Shader Transpiler: get_transpiled target does not support paired graphics shaders for this backend.", loc=loc);
    return "";
  }

  fragment_name := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
  if !fragment_name {
    compiler_report("Jai Shader Transpiler: get_transpiled fragment argument must be a procedure identifier.", loc=loc);
    return "";
  }

  request_name := tprint("transpiled_pair_%_%_%", target_ident, shader_name, fragment_name);
  to_lower_in_place(request_name);
  key := tprint("pair|%|%|%", pair_note, shader_name, fragment_name);
  request_source := tprint("% :: %; @%(%)\n", request_name, shader_name, pair_note, fragment_name);
  ensure_get_transpiled_request_registered(key, request_source);
  return tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", target_expr, shader_name, fragment_name);
}

get_transpiled :: (target: Transpiled_Target, args: ..Any, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> string #expand {
    #insert #run -> string {
        workspace := get_current_workspace();
        return tprint(#string END
G :: #import,file "%";
return %;
END, compute_path_to_shader_bucket_module(workspace), get_transpiled_result_expr_from_call(call, loc));
    };
}

convert_procs :: (p: *Metaprogram_Plugin, message: *Message) {
  plugin := cast(*Jai_To_Shader_Plugin) p;
  
  assert(plugin.did_add_setup_source, "Your compiler message loop needs to call plugin.add_source first");

  if message.kind == {
    case .TYPECHECKED; {
      tc := cast(*Message_Typechecked) message;
      for tc.procedure_bodies {
        proc := it.expression;
        already := false;
        for note: proc.header.notes {
            if note.text == {
            case "compute_shader"; #through;
            case "vertex_shader"; #through;
            case "fragment_shader";
              array_add_if_unique(*plugin.known_procedure_bodies, proc);
              break;
            }
        }
      }
      for tc.declarations {
        resolved := collect_shader_requests_from_declaration(plugin, it.expression, plugin.known_procedure_bodies);
        if !resolved {
          add_pending_request_declaration(plugin, it.expression);
        }
      }
      for plugin.pending_request_declarations {
        if collect_shader_requests_from_declaration(plugin, it, plugin.known_procedure_bodies) {
          remove it;
        }
      }
    }
    
    case .PHASE; {
      phase := cast(*Message_Phase) message;
      if phase.phase == .TYPECHECKED_ALL_WE_CAN {
        array_reset(*plugin.manifest_entries);
        workspace_root := get_working_directory();
        if !plugin.did_log_ir_pipeline {
          plugin.did_log_ir_pipeline = true;
        }

        for * pair_ctx: plugin.currently_waiting_pair_contexts {
          s: string;
          used_ir_pipeline := false;
          {
            s2, ok2, diag := write_shader_pair_ir_spirv(pair_ctx);
            if ok2 {
              s = s2;
              used_ir_pipeline = true;
            } else {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader pair '%'.", pair_ctx.name);
              if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
              if diag.has_location compiler_report(report_message, diag.location);
              else compiler_report(report_message, make_location(pair_ctx.vertex_fn.header));
              remove pair_ctx;
              continue;
            }
          }

          assert(s != "");
          add_code(plugin, s, "waiting_pairs");

          if plugin.output_shaders {
            ext := tprint("%", pair_ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, pair_ctx.name, ext);
            ok := false;
            ir_source_path := ir_output_path_from_pair_context(pair_ctx);
            file_source, read_ok := read_entire_file(ir_source_path);
            if !read_ok {
              log_error("Error reading IR output file '%'", ir_source_path);
              assert(false);
            }
            ok = write_entire_file(filename, file_source);
            if !ok {
              log_error("Error writing file to '%'", filename);
            } else {
              #if VERBOSE log("Transpiled Jai pair shader to %", filename);
            }
          }

          manifest_entry := manifest_make_pair_entry(pair_ctx, workspace_root);
          if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);

          remove pair_ctx;
        }

        {
          jobs: [..] SPV_External_Single_Job;
          for *ctx: plugin.currently_waiting_contexts {
            job: SPV_External_Single_Job;
            prep_ok, prep_diag := prepare_single_spirv_external_job(ctx, *job);
            if !prep_ok {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if prep_diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, prep_diag.message);
              if prep_diag.has_location compiler_report(report_message, prep_diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              continue;
            }
            array_add(*jobs, job);
          }

          run_spirv_external_jobs_parallel(jobs);

          for *jobs {
            ctx := it.ctx;
            source, finalize_ok, finalize_diag := finalize_single_spirv_external_job(it, add_generated_comment=true);
            if !finalize_ok {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if finalize_diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, finalize_diag.message);
              if finalize_diag.has_location compiler_report(report_message, finalize_diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              continue;
            }

            s := tprint("% :: #string END\n%\nEND", ir_symbol_name_from_context(ctx), source);
            add_code(plugin, s, "jobs");
            if plugin.output_shaders {
              ext := tprint("%", ctx.language);
              to_lower_in_place(ext);
              make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
              filename := tprint("%/%.%", DEBUG_OUTDIR, ctx.name, ext);
              ok := false;
              ir_source_path := ir_output_path_from_context(ctx);
              file_source, read_ok := read_entire_file(ir_source_path);
              if !read_ok {
                log_error("Error reading IR output file '%'", ir_source_path);
                assert(false);
              }
              ok = write_entire_file(filename, file_source);
              if !ok {
                log_error("Error writing file to '%'", filename);
              } else {
                #if VERBOSE log("Transpiled Jai to %", filename);
              }
            }
            manifest_entry := manifest_make_single_entry(ctx, workspace_root);
            if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);
          }
          array_reset(*plugin.currently_waiting_contexts);
        }

        if plugin.manifest_entries.count > 0 emit_shader_reload_manifest(plugin);

        emit_lookup_overloads(plugin, p.workspace);
      }
    }
    
    case .COMPLETE; {
      using,except(message, plugin) plugin;
      if currently_waiting_contexts.count != 0 || currently_waiting_pair_contexts.count != 0 {
        complete_message := cast(*Message_Complete)message;
        if complete_message.error_code == 0 {
          compiler_report("Jai Shader Transpiler: Compiler is finished, but some functions have not yet been transpiled.");
        }
      }
      array_reset(*currently_waiting_contexts);
      array_reset(*currently_waiting_pair_contexts);
      array_reset(*pending_request_declarations);
      array_reset(*known_procedure_bodies);
      array_reset(*lookup_entries);
      array_reset(*manifest_entries);
      did_emit_lookup_overloads = false;
      did_log_ir_pipeline = false;
      did_log_ir_limitations = false;
      table_reset(*get_transpiled_requests_seen);
    }
  }
}

_before_intercept :: (p: *Metaprogram_Plugin, intercept_flags: *Intercept_Flags) {
}

_add_source :: (p: *Metaprogram_Plugin) {
    // Here at the beginning of the compiler loop, we generate a .jai file in the intermediate directory.
    // We can use that generated module as a known-good place in this workspace to #poke_name our generated
    // shader strings into later, and also to look them up via get_transpiled.
    assert(p.workspace > 0);
    path_to_generated_source := compute_path_to_shader_bucket_module(p.workspace);
    make_directory_if_it_does_not_exist(path_strip_filename(path_to_generated_source), recursive=true);
    ok := write_entire_file(path_to_generated_source, #string END
// Auto-generated from Jai_To_Shader's _add_source
#scope_export

#placeholder lookup_transpiled_impl;

lookup_transpiled :: (target_name: string, primary_name: string, secondary_name: string) -> string {
    return lookup_transpiled_impl(target_name, primary_name, secondary_name);
}
END);
    assert(ok);
    
    plugin := cast(*Jai_To_Shader_Plugin)p;
    add_build_file(path_to_generated_source, p.workspace);
    plugin.did_add_setup_source = true;
}

compute_path_to_shader_bucket_module :: (workspace: Workspace) -> string {
    assert(workspace > 0);
    opts := get_build_options(workspace);
    path := sprint("%/jst_generated.jai", opts.intermediate_path);
    return path;
}

ir_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.language != .METAL && !(ctx.language == .GLSL && ctx.glsl_target == .VULKAN) return false;
  return ctx.type == .Vertex || ctx.type == .Fragment || ctx.type == .Compute;
}

ir_symbol_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.language == .METAL return tprint("%_metal_string", ctx.name);
  return tprint("%_string", ctx.name);
}



ir_target_from_context :: (ctx: *Shader_Write_Context) -> (Toolchain_Target, bool) {
  if ctx.language == .METAL return .METAL, true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return .VULKAN_GLSL, true;
  return .METAL, false;
}

ir_stage_short_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.type == .Vertex return "vert";
  if ctx.type == .Compute return "comp";
  return "frag";
}

ir_output_ext_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.language == .METAL return "metal";
  return "glsl";
}

ir_output_path_from_context :: (ctx: *Shader_Write_Context) -> string {
  return tprint("%/%.%", DEBUG_OUTDIR, ctx.name, ir_output_ext_from_context(ctx));
}

ir_output_path_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  return tprint("%/%.metal", DEBUG_OUTDIR, pair_ctx.name);
}

is_internal_transpiled_request_name :: (name: string) -> bool {
  return begins_with(name, "transpiled_single_") || begins_with(name, "transpiled_pair_");
}

ir_metal_enable_unsafe_runtime_array_indexing :: (source: string) -> string {
  out := source;
  // SPIRV-Cross can emit a generic signed-mod helper that uses `select(...)`
  // in a way Metal may treat as ambiguous for 64-bit integer template params.
  out = replace(out,
                "return select(Tx(remainder + y), remainder, remainder == 0 || (x >= 0) == (y >= 0));",
                "return (remainder == 0 || (x >= 0) == (y >= 0)) ? remainder : Tx(remainder + y);");
  return out;
}

ir_source_file_from_proc :: (proc: *Code_Procedure_Body) -> string {
  if !proc || !proc.header return "";
  loc := make_location(proc.header);
  return loc.fully_pathed_filename;
}

ir_source_file_from_context :: (ctx: *Shader_Write_Context) -> string {
  if !ctx return "";
  return ir_source_file_from_proc(ctx.main_fn);
}

ir_source_file_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  if !pair_ctx return "";
  vertex_file := ir_source_file_from_proc(pair_ctx.vertex_fn);
  fragment_file := ir_source_file_from_proc(pair_ctx.fragment_fn);
  if vertex_file.count == 0 return fragment_file;
  if fragment_file.count == 0 return vertex_file;
  if vertex_file == fragment_file return vertex_file;
  return tprint("% | %", vertex_file, fragment_file);
}

ir_pipeline_label_spirv :: (target: Toolchain_Target) -> string {
  if target == .METAL return "Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal";
  return "Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL";
}

ir_prepend_generated_comment :: (target_source: string, source_jai_file: string, pipeline_label: string) -> string {
  jai_file := source_jai_file;
  if jai_file.count == 0 jai_file = "<unknown>";
  return tprint("// Generated from % with (<<%>>)\n%", jai_file, pipeline_label, target_source);
}

ir_spirv_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.type != .Vertex && ctx.type != .Fragment && ctx.type != .Compute return false;
  if ctx.language == .METAL return true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return true;
  return false;
}

ir_lowered_struct_has_resource_fields :: (structs: [] IR_Struct, struct_name: string, depth := 0) -> bool {
  if struct_name.count == 0 return false;
  if depth > 16 return false;
  for structs {
    if it.name != struct_name continue;
    for it.fields {
      if it.type.kind == .POINTER return true;
      nested_name := it.type.struct_name;
      if ir_lowered_struct_has_resource_fields(structs, nested_name, depth + 1) return true;
    }
    return false;
  }
  return false;
}

ir_graphics_requires_metal_argument_buffer :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool {
  for args {
    if it.type.kind == .POINTER return true;
    struct_name := it.type.struct_name;
    if ir_lowered_struct_has_resource_fields(extra_structs, struct_name) return true;
  }
  return false;
}

SPV_External_Single_Job :: struct {
  ctx: *Shader_Write_Context;
  validate_before_opt: bool;
  stage: IR_Shader_Kind;
  target: Toolchain_Target;
  entry_name: string;
  use_metal_argument_buffers: bool;
  spvasm_path: string;
  spv_path: string;
  spv_opt_path: string;
  output_path: string;

  ok: bool;
  error_message: string;
}

prepare_single_spirv_external_job :: (ctx: *Shader_Write_Context, job: *SPV_External_Single_Job) -> (ok: bool, diag: IR_Diagnostic) {
  assert(ctx != null && job != null);
  
  return_err :: (msg: string) #expand {
      diag: IR_Diagnostic = { message = msg };
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      `return false, diag;
  }

  diag: IR_Diagnostic;
  if !ir_spirv_supports_single_context(ctx)
      return_err("SPIR-V backend currently supports vertex/fragment/compute shaders targeting Metal or Vulkan GLSL only.");

  target, target_ok := ir_target_from_context(ctx);
  if !target_ok
      return_err("SPIR-V backend: unsupported target for context.");

  spvasm_source: string;
  spvasm_ok := false;
  spvasm_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;

  if ctx.type == .Vertex {
    vert_result := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_vertex, lowered, lowered_diag := unpack_result(vert_result);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_vertex);
    entry_name = ir_vertex.entry_name;
    vert_spvasm_res := to_spvasm(*ir_vertex);
    spvasm_source, spvasm_ok, spvasm_diag = unpack_result(vert_spvasm_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    frag_lower_res := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_fragment, lowered, lowered_diag := unpack_result(frag_lower_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_fragment);
    entry_name = ir_fragment.entry_name;
    
    frag_spvasm_res := to_spvasm(*ir_fragment);
    spvasm_source, spvasm_ok, spvasm_diag = unpack_result(frag_spvasm_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    lower_compute_res := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_compute, lowered, lowered_diag := unpack_result(lower_compute_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_compute);
    entry_name = ir_compute.entry_name;
    compute_spvasm_res := to_spvasm(*ir_compute);
    spvasm_source, spvasm_ok, spvasm_diag = unpack_result(compute_spvasm_res);
  }

  if entry_name.count == 0
      return_err("SPIR-V backend: empty entry name.");

  if !spvasm_ok {
    if spvasm_diag.message.count == 0 spvasm_diag.message = tprint("SPIR-V text backend: failed to emit SPIR-V assembly for '%'.", ctx.name);
    if !spvasm_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spvasm_diag.location = make_location(ctx.main_fn.header);
      spvasm_diag.has_location = true;
    }
    return false, spvasm_diag;
  }

  build_dir := IR_INTERMEDIATE_DIR;
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  stage_short := ir_stage_short_from_context(ctx);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";

  job.ctx = ctx;
  job.validate_before_opt = false;
  job.stage = ctx.type;
  job.target = target;
  job.entry_name = copy_string(entry_name);
  job.use_metal_argument_buffers = use_metal_argument_buffers;
  job.spvasm_path = sprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  job.spv_path = sprint("%/%_%.spv", build_dir, ctx.name, stage_short);
  job.spv_opt_path = sprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short);
  job.output_path = sprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);
  job.ok = false;
  job.error_message = "";

  if !write_entire_file(job.spvasm_path, spvasm_source) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V text file '%'.", job.spvasm_path);
    return false, diag;
  }

  return true, diag;
}

run_spirv_external_single_job :: (job: *SPV_External_Single_Job) -> bool {
  assert(job != null);
  if !assemble_spirv_text(job.spvasm_path, job.spv_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: failed assembling SPIR-V text for '%'. Source: %", job.ctx.name, job.spvasm_path));
    return false;
  }

  if job.validate_before_opt {
    if !validate_spirv_binary(job.spv_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
  }

  if USE_SPIRV_OPT {
    if !optimize_spirv_binary(job.spv_path, job.spv_opt_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
  } else {
    job.spv_opt_path = job.spv_path;
  }

  if !validate_spirv_binary(job.spv_opt_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }

  if !emit_spirv_cross_target_source(job.spv_opt_path, job.entry_name, job.stage, job.target, job.output_path, job.use_metal_argument_buffers, source_entry_name=job.entry_name) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }

  return true;
}

spv_external_single_worker_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
  _ = group;
  _ = thread;
  job := cast(*SPV_External_Single_Job) work;
  job.ok = run_spirv_external_single_job(job);
  return .CONTINUE;
}

run_spirv_external_jobs_parallel :: (jobs: [] SPV_External_Single_Job) {
  if jobs.count == 0 return;
  cpus := get_number_of_processors();
  if cpus < 1 cpus = 1;
  job_count := cast(s32) jobs.count;
  worker_count := min(max(cpus - 1, 1), job_count);
  tg: Thread_Group;
  init(*tg, worker_count, spv_external_single_worker_proc);
  tg.logging = false;
  tg.name = "JTS-SPV-External";
  start(*tg);
  defer shutdown(*tg);

  for *jobs add_work(*tg, it);

  completed := 0;
  while completed < jobs.count {
    done := get_completed_work(*tg);
    completed += done.count;
    if completed < jobs.count sleep_milliseconds(1);
  }
}

finalize_single_spirv_external_job :: (job: *SPV_External_Single_Job, add_generated_comment := true) -> (target_source: string, ok: bool, diag: IR_Diagnostic) {
  assert(job != null);
  diag: IR_Diagnostic;
  if !job.ok {
    diag.message = ifx job.error_message.count != 0 then job.error_message else "SPIR-V backend: external toolchain step failed.";
    if job.ctx && job.ctx.main_fn && job.ctx.main_fn.header {
      diag.location = make_location(job.ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  target_source, read_ok := read_entire_file(job.output_path);
  if !read_ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", job.output_path);
    return "", false, diag;
  }

  if job.ctx.language == .METAL && job.ctx.type != .Compute {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    write_entire_file(job.output_path, target_source);
  }
  if job.ctx.type == .Compute && job.ctx.language == .METAL {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(job.ctx), ir_pipeline_label_spirv(job.target));
  }
  write_entire_file(job.output_path, target_source);

  return target_source, true, diag;
}

ir_emit_single_spirv_target_source :: (ctx: *Shader_Write_Context, add_generated_comment := true) -> (string, string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !ir_spirv_supports_single_context(ctx) {
    diag.message = "SPIR-V backend currently supports vertex/fragment/compute shaders targeting Metal or Vulkan GLSL only.";
    if ctx && ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  spvasm_source: string;
  spvasm_ok := false;
  spvasm_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;
  if ctx.type == .Vertex {
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    normalized, normalize_diag := normalize_vertex_ir(*ir_vertex);
    if !normalized return "", "", false, normalize_diag;
    entry_name = ir_vertex.entry_name;
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_vertex_to_spirv_text_branch(ir_vertex);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    normalized, normalize_diag := normalize_shader(*ir_fragment);
    if !normalized return "", "", false, normalize_diag;
    entry_name = ir_fragment.entry_name;
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_fragment_to_spirv_text_branch(ir_fragment);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    normalized, normalize_diag := normalize_compute_ir(*ir_compute);
    if !normalized return "", "", false, normalize_diag;
    entry_name = ir_compute.entry_name;
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_compute_to_spirv_text_branch(ir_compute);
  }

  target, target_ok := ir_target_from_context(ctx);
  if !target_ok {
    diag.message = "SPIR-V backend: unsupported target for context.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  build_dir := IR_INTERMEDIATE_DIR;
  make_directory_if_it_does_not_exist(build_dir, recursive=true);

  stage_short := ir_stage_short_from_context(ctx);
  spv_path := tprint("%/%_%.spv", build_dir, ctx.name, stage_short);
  spv_opt_path := tprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";
  output_path := tprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);

  if entry_name.count == 0 {
    diag.message = "SPIR-V backend: empty entry name.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  if !spvasm_ok {
    if spvasm_diag.message.count == 0 spvasm_diag.message = tprint("SPIR-V text backend: failed to emit SPIR-V assembly for '%'.", ctx.name);
    if !spvasm_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spvasm_diag.location = make_location(ctx.main_fn.header);
      spvasm_diag.has_location = true;
    }
    return "", "", false, spvasm_diag;
  }
  spvasm_path := tprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  if !write_entire_file(spvasm_path, spvasm_source) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V text file '%'.", spvasm_path);
    return "", "", false, diag;
  }
  if !assemble_spirv_text(spvasm_path, spv_path) {
    diag.message = tprint("SPIR-V backend: failed assembling SPIR-V text for '%'. Source: %", ctx.name, spvasm_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  spv_for_target := spv_path;
  if !optimize_spirv_binary(spv_path, spv_opt_path) {
    diag.message = tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", ctx.name, spv_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  spv_for_target = spv_opt_path;

  if !validate_spirv_binary(spv_for_target) {
    diag.message = tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  if !emit_spirv_cross_target_source(spv_for_target, entry_name, ctx.type, target, output_path, use_metal_argument_buffers, source_entry_name=entry_name) {
    diag.message = tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  target_source, ok := read_entire_file(output_path);
  if !ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", output_path);
    return "", "", false, diag;
  }
  if ctx.language == .METAL && ctx.type != .Compute {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    write_entire_file(output_path, target_source);
  }
  if ctx.type == .Compute && ctx.language == .METAL {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(ctx), ir_pipeline_label_spirv(target));
  }
  make_directory_if_it_does_not_exist(path_strip_filename(output_path), recursive=true);
  write_entire_file(output_path, target_source);

  return target_source, output_path, true, diag;
}

write_shader_single_ir_spirv :: (ctx: *Shader_Write_Context) -> (string, bool, IR_Diagnostic) {
  target_source, _, ok, diag := ir_emit_single_spirv_target_source(ctx, add_generated_comment=true);
  if !ok return "", false, diag;

  symbol_name := ir_symbol_name_from_context(ctx);
  decl := tprint("% :: #string END\n%\nEND", symbol_name, target_source);
  return decl, true, diag;
}

ir_semantic_upper_local :: (semantic: string) -> string {
  if semantic.count == 0 return "";
  return to_upper_copy(trim(semantic));
}

ir_vertex_output_field_is_builtin_local :: (field: *IR_Field) -> bool {
  if !field return false;
  sem := ir_semantic_upper_local(field.semantic);
  if sem == "SV_POSITION" || sem == "GL_POSITION" || sem == "POSITION" return true;
  if sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return true;
  return false;
}

ir_fragment_input_field_is_builtin_local :: (field: *IR_Field) -> bool {
  if !field return false;
  if field.name == "gl_FragCoord" return true;
  sem := ir_semantic_upper_local(field.semantic);
  if sem == "SV_POSITION" || sem == "POSITION" || sem == "GL_POSITION" || sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return true;
  return false;
}

ir_pair_varying_field_label_local :: (field: *IR_Field) -> string {
  if !field return "<null>";
  if field.semantic.count != 0 return tprint("% (semantic %)", field.name, field.semantic);
  return field.name;
}

ir_pair_varyings_match_local :: (vertex_field: *IR_Field, fragment_field: *IR_Field) -> bool {
  assert(vertex_field != null);
  assert(fragment_field != null);

  vertex_sem := ir_semantic_upper_local(vertex_field.semantic);
  fragment_sem := ir_semantic_upper_local(fragment_field.semantic);
  if vertex_sem.count != 0 && fragment_sem.count != 0 return vertex_sem == fragment_sem;
  return vertex_field.name == fragment_field.name;
}

ir_type_text_local :: (type: IR_Type) -> string {
  if type.display_name.count != 0 return type.display_name;
  if type.struct_name.count != 0 return type.struct_name;
  return "<unknown>";
}

ir_types_equal_local :: (a: IR_Type, b: IR_Type) -> bool {
  if a.kind != b.kind return false;
  if a.flags != b.flags return false;
  if a.struct_name != b.struct_name return false;
  if a.array_count != b.array_count return false;
  if a.element_kind != b.element_kind return false;
  if a.element_struct_name != b.element_struct_name return false;
  if a.pointee_kind != b.pointee_kind return false;
  if a.pointee_struct_name != b.pointee_struct_name return false;
  if a.pointee_array_count != b.pointee_array_count return false;
  if a.pointee_element_kind != b.pointee_element_kind return false;
  if a.pointee_element_struct_name != b.pointee_element_struct_name return false;
  return true;
}

ir_validate_pair_stage_interface_local :: (pair_name: string, vertex: *IR_Vertex_Shader, fragment: *IR_Fragment_Shader) -> (bool, string) {
    auto_release_temp();
  assert(vertex != null && fragment != null);

  vertex_varyings:   [..] IR_Field;
  vertex_varyings.allocator = temp;
  
  fragment_varyings: [..] IR_Field;
  fragment_varyings.allocator = temp;
  
  for vertex.output.fields {
    if ir_vertex_output_field_is_builtin_local(*it) continue;
    array_add(*vertex_varyings, it);
  }
  for fragment.input.fields {
    if ir_fragment_input_field_is_builtin_local(*it) continue;
    array_add(*fragment_varyings, it);
  }

  if vertex_varyings.count != fragment_varyings.count {
    return false, sprint("SPIR-V backend: pair '%': stage interface mismatch: vertex exports % user varyings but fragment consumes %.", pair_name, vertex_varyings.count, fragment_varyings.count);
  }

  for i: 0..fragment_varyings.count-1 {
    v := vertex_varyings[i];
    f := fragment_varyings[i];
    if !ir_types_equal_local(v.type, f.type) {
      return false, sprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' has type '%', fragment '%' has type '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), ir_type_text_local(v.type), ir_pair_varying_field_label_local(*f), ir_type_text_local(f.type));
    }
    if !ir_pair_varyings_match_local(*v, *f) {
      return false, sprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' does not match fragment '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), ir_pair_varying_field_label_local(*f));
    }
  }

  return true, "";
}

write_shader_pair_ir_spirv :: (pair_ctx: *Shader_Write_Pair_Context) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !ir_supports_pair_context(pair_ctx) {
    diag.message = "SPIR-V backend: unsupported shader pair context/target combination.";
    if pair_ctx && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  vertex_ctx := create_shader_write_context(.METAL, pair_ctx.vertex_fn, pair_ctx.glsl_target);
  fragment_ctx := create_shader_write_context(.METAL, pair_ctx.fragment_fn, pair_ctx.glsl_target);

  vert_result := ir_lower_vertex_from_shader_context(.{name=vertex_ctx.name, header=vertex_ctx.main_fn.header});
  ir_vertex, vertex_ok, vertex_diag := unpack_result(vert_result);
  if !vertex_ok {
    if !vertex_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      vertex_diag.location = make_location(pair_ctx.vertex_fn.header);
      vertex_diag.has_location = true;
    }
    return "", false, vertex_diag;
  }
  normalize_shader(*ir_vertex);

  frag_result := ir_lower_fragment_from_shader_context(.{name=fragment_ctx.name, header=fragment_ctx.main_fn.header});
  ir_fragment, fragment_ok, fragment_diag := unpack_result(frag_result);
  
  if !fragment_ok {
    if !fragment_diag.has_location && pair_ctx.fragment_fn && pair_ctx.fragment_fn.header {
      fragment_diag.location = make_location(pair_ctx.fragment_fn.header);
      fragment_diag.has_location = true;
    }
    return "", false, fragment_diag;
  }
  normalize_shader(*ir_fragment);

  vertex_uses_pointer_abi   := ir_uses_pointer_abi_local(ir_vertex.args, ir_vertex.extra_structs);
  fragment_uses_pointer_abi := ir_uses_pointer_abi_local(ir_fragment.args, ir_fragment.extra_structs);
  
  if vertex_uses_pointer_abi != fragment_uses_pointer_abi {
    diag.message = tprint("SPIR-V backend: pair '%': vertex and fragment use incompatible resource ABI styles (vertex pointer-ABI=%; fragment pointer-ABI=%). Pair shaders must agree on resource ABI.", pair_ctx.name, vertex_uses_pointer_abi, fragment_uses_pointer_abi);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  interface_ok, interface_err := ir_validate_pair_stage_interface_local(pair_ctx.name, *ir_vertex, *ir_fragment);
  if !interface_ok {
    diag.message = interface_err;
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  // Keep direct bindings by default for pair shaders, but switch to argument buffers when
  // bindless globals are present in SPIR-V text (required for large bindless arrays on Metal).
  use_metal_argument_buffers := false;
  
  
  // TODO: remove this
  emit_ir_graphics_pair_to_spirv_text_branch :: (vertex: IR_Vertex_Shader, fragment: IR_Fragment_Shader) -> (vertex_spvasm: string, fragment_spvasm: string, ok: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    assert(vertex.entry_name.count != 0);
    assert(fragment.entry_name.count != 0);
    
    vert_spvasm_res := to_spvasm(*vertex);
    vertex_spv, vertex_ok, vertex_diag := unpack_result(vert_spvasm_res);
    if !vertex_ok return "", "", false, vertex_diag;
    
    frag_spvasm_res := to_spvasm(*fragment);
    fragment_spv, fragment_ok, fragment_diag := unpack_result(frag_spvasm_res);
    if !fragment_ok return "", "", false, fragment_diag;
    
    return vertex_spv, fragment_spv, true, diag;
  }

  vertex_spvasm, fragment_spvasm, pair_spvasm_ok, pair_spvasm_diag := emit_ir_graphics_pair_to_spirv_text_branch(ir_vertex, ir_fragment);
  if !pair_spvasm_ok {
    if !pair_spvasm_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      pair_spvasm_diag.location = make_location(pair_ctx.vertex_fn.header);
      pair_spvasm_diag.has_location = true;
    }
    return "", false, pair_spvasm_diag;
  }
  build_dir := IR_INTERMEDIATE_DIR;
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  vertex_spvasm_path := tprint("%/%_vert.spvasm", build_dir, pair_ctx.name);
  fragment_spvasm_path := tprint("%/%_frag.spvasm", build_dir, pair_ctx.name);
  vertex_spv_path := tprint("%/%_vert.spv", build_dir, pair_ctx.name);
  fragment_spv_path := tprint("%/%_frag.spv", build_dir, pair_ctx.name);
  pair_spv_path := tprint("%/%_pair.spv", build_dir, pair_ctx.name);
  pair_opt_spv_path := tprint("%/%_pair.opt.spv", build_dir, pair_ctx.name);
  pair_spvasm_path := tprint("%/%_pair.spvasm", build_dir, pair_ctx.name);
  vertex_output_path := tprint("%/%_vert.metal", build_dir, pair_ctx.name);
  fragment_output_path := tprint("%/%_frag.metal", build_dir, pair_ctx.name);
  if !write_entire_file(vertex_spvasm_path, vertex_spvasm) || !write_entire_file(fragment_spvasm_path, fragment_spvasm) {
    diag.message = "SPIR-V backend: failed writing pair SPIR-V text files.";
    return "", false, diag;
  }
  if !assemble_spirv_text(vertex_spvasm_path, vertex_spv_path) || !assemble_spirv_text(fragment_spvasm_path, fragment_spv_path) {
    diag.message = "SPIR-V backend: failed assembling pair SPIR-V text.";
    return "", false, diag;
  }
  if !link_spirv_binaries(.[vertex_spv_path, fragment_spv_path], pair_spv_path) {
    vertex_model := spv_memory_model_from_text(vertex_spvasm);
    fragment_model := spv_memory_model_from_text(fragment_spvasm);
    if vertex_model.count != 0 || fragment_model.count != 0 {
      diag.message = tprint("SPIR-V backend: spirv-link failed for pair module (vertex model='%'; fragment model='%').", vertex_model, fragment_model);
    } else {
      diag.message = "SPIR-V backend: spirv-link failed for pair module.";
    }
    return "", false, diag;
  }
  if !optimize_spirv_binary(pair_spv_path, pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for pair module.";
    return "", false, diag;
  }
  if !validate_spirv_binary(pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for pair module.";
    return "", false, diag;
  }
  if !disassemble_spirv_binary(pair_opt_spv_path, pair_spvasm_path) {
    diag.message = "SPIR-V backend: spirv-dis failed for optimized pair module.";
    return "", false, diag;
  }
  if !emit_spirv_cross_target_source(pair_opt_spv_path, "VertexMain", .Vertex, .METAL, vertex_output_path, use_metal_argument_buffers, source_entry_name="VertexMain") {
    diag.message = "SPIR-V backend: pair vertex spirv-cross failed.";
    return "", false, diag;
  }
  if !emit_spirv_cross_target_source(pair_opt_spv_path, "FragmentMain", .Fragment, .METAL, fragment_output_path, use_metal_argument_buffers, source_entry_name="FragmentMain") {
    diag.message = "SPIR-V backend: pair fragment spirv-cross failed.";
    return "", false, diag;
  }

  vertex_source, v_ok   := read_entire_file(vertex_output_path);
  fragment_source, f_ok := read_entire_file(fragment_output_path);
  if !v_ok || !f_ok {
    diag.message = "SPIR-V backend: failed reading pair spirv-cross outputs.";
    return "", false, diag;
  }

  vertex_source = ir_metal_enable_unsafe_runtime_array_indexing(vertex_source);
  fragment_source = ir_metal_enable_unsafe_runtime_array_indexing(fragment_source);
  _ = write_entire_file(vertex_output_path, vertex_source);
  _ = write_entire_file(fragment_output_path, fragment_source);

  merged_source := ir_merge_metal_pair_sources(vertex_source, fragment_source);
  merged_source = ir_metal_enable_unsafe_runtime_array_indexing(merged_source);
  merged_source = ir_prepend_generated_comment(merged_source, ir_source_file_from_pair_context(pair_ctx), ir_pipeline_label_spirv(.METAL));
  output_path := ir_output_path_from_pair_context(pair_ctx);
  make_directory_if_it_does_not_exist(path_strip_filename(output_path), recursive=true);
  if !write_entire_file(output_path, merged_source) {
    diag.message = tprint("SPIR-V backend: failed writing merged pair source '%'.", output_path);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  decl := tprint("%_metal_string :: #string END\n%\nEND", pair_ctx.name, merged_source);
  return decl, true, diag;
}

ir_supports_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> bool {
  if !pair_ctx return false;
  if pair_ctx.language != .METAL return false;
  return pair_ctx.vertex_fn != null && pair_ctx.fragment_fn != null;
}

shader_request_name_to_language :: (name: string) -> (Shader_Language, GLSL_Target, bool) {
  if name == {
    case "shader_to_glsl";   return .GLSL,  .OPENGL, true;
    case "shader_to_vulkan"; return .GLSL,  .VULKAN, true;
    case "shader_to_hlsl";   return .HLSL,  .OPENGL, true;
    case "shader_to_metal";  return .METAL, .OPENGL, true;
    case; return .NONE, .OPENGL, false;
  }
}

target_name_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == {
    case .METAL; return ".METAL";
    case .HLSL;  return ".HLSL";
    case .GLSL;  return ifx glsl_target == .VULKAN then ".VULKAN_GLSL" else ".OPENGL_GLSL";
  }
  return "";
}

trim_ascii_whitespace :: (in: string) -> string {
  if in.count == 0 return in;

  start := cast(s64) 0;
  end := in.count - 1;
  while start <= end && (in[start] == #char " " || in[start] == #char "\t" || in[start] == #char "\n" || in[start] == #char "\r")
    start += 1;
  while end >= start && (in[end] == #char " " || in[end] == #char "\t" || in[end] == #char "\n" || in[end] == #char "\r")
    end -= 1;

  ret: string;
  ret.data = in.data + start;
  ret.count = end - start + 1;
  return ret;
}

lookup_entry_already_queued :: (plugin: *Jai_To_Shader_Plugin, target_name: string, primary_name: string, secondary_name: string, symbol_name: string) -> bool {
  for plugin.lookup_entries {
    if it.target_name != target_name continue;
    if it.primary_name != primary_name continue;
    if it.secondary_name != secondary_name continue;
    if it.symbol_name != symbol_name continue;
    return true;
  }
  return false;
}

queue_lookup_entry :: (plugin: *Jai_To_Shader_Plugin, target_name: string, primary_name: string, secondary_name: string, symbol_name: string) {
  if lookup_entry_already_queued(plugin, target_name, primary_name, secondary_name, symbol_name) return;
  array_add(*plugin.lookup_entries, .{
    target_name = target_name,
    primary_name = primary_name,
    secondary_name = secondary_name,
    symbol_name = symbol_name,
  });
}

emit_lookup_overloads :: (plugin: *Jai_To_Shader_Plugin, workspace: Workspace) {
  if plugin.did_emit_lookup_overloads return;
  plugin.did_emit_lookup_overloads = true;

  sb: String_Builder;
  append_lines(*sb,
    tprint("G :: #import,file \"%\";", compute_path_to_shader_bucket_module(plugin.workspace)),
    "#poke_name G lookup_transpiled_impl;",
    "lookup_transpiled_impl :: (target_name: string, primary_name: string, secondary_name: string) -> string {",
  );
  for plugin.lookup_entries {
    a(*sb, "  if target_name == \"%\" && primary_name == \"%\" && secondary_name == \"%\" return %;",
                       it.target_name, it.primary_name, it.secondary_name, it.symbol_name);
  }
  a(*sb, "  return \"\";\n}");

  add_code(plugin, builder_to_string(*sb), "lookup_overloads");
}

parse_shader_pair_note :: (note_text: string) -> (Shader_Language, GLSL_Target, string, bool, bool) {
  prefixes := string.[
    "shader_pair_to_glsl(",
    "shader_pair_to_vulkan(",
    "shader_pair_to_metal(",
  ];

  languages := Shader_Language.[.GLSL, .GLSL, .METAL];
  targets   := GLSL_Target.[.OPENGL, .VULKAN, .OPENGL];

  for prefixes {
    prefix := it;
    if !begins_with(note_text, prefix) continue;

    rest: string = { note_text.count - prefix.count, note_text.data + prefix.count };
    if rest.count == 0 return .NONE, .OPENGL, "", true, false;

    close_paren_index: s64 = -1;
    for i: 0..rest.count-1 {
      if rest[i] == #char ")" {
        close_paren_index = i;
        break;
      }
    }
    if close_paren_index == -1 return .NONE, .OPENGL, "", true, false;

    arg: string = { close_paren_index, rest.data };
    arg = trim_ascii_whitespace(arg);
    if arg.count == 0 return .NONE, .OPENGL, "", true, false;

    trailing: string = { rest.count - (close_paren_index + 1), rest.data + close_paren_index + 1 };
    trailing = trim_ascii_whitespace(trailing);
    if trailing.count != 0 return .NONE, .OPENGL, "", true, false;

    return languages[it_index], targets[it_index], arg, true, true;
  }

  return .NONE, .OPENGL, "", false, false;
}

context_already_queued :: (plugin: *Jai_To_Shader_Plugin, language: Shader_Language, proc: *Code_Procedure_Body, glsl_target: GLSL_Target) -> bool {
  for *plugin.currently_waiting_contexts {
    if it.main_fn != proc continue;
    if it.language != language continue;
    if it.glsl_target != glsl_target continue;
    return true;
  }
  return false;
}

pair_context_already_queued :: (plugin: *Jai_To_Shader_Plugin, language: Shader_Language, vertex: *Code_Procedure_Body, fragment: *Code_Procedure_Body, glsl_target: GLSL_Target) -> bool {
  for *plugin.currently_waiting_pair_contexts {
    if it.vertex_fn != vertex continue;
    if it.fragment_fn != fragment continue;
    if it.language != language continue;
    if it.glsl_target != glsl_target continue;
    return true;
  }
  return false;
}

add_pending_request_declaration :: (plugin: *Jai_To_Shader_Plugin, decl: *Code_Declaration) {
  if !decl return;
  for plugin.pending_request_declarations if it == decl return;
  array_add(*plugin.pending_request_declarations, decl);
}

resolve_shader_request_target :: (arg: *Code_Node, procedure_bodies: [] *Code_Procedure_Body) -> *Code_Procedure_Body {
  if !arg return null;
  if arg.kind == {
    case .PROCEDURE_BODY;
      return cast(*Code_Procedure_Body) arg;
    case .PROCEDURE_HEADER; {
      header := cast(*Code_Procedure_Header) arg;
      return header.body_or_null;
    }
    case .IDENT; {
      ident := cast(*Code_Ident) arg;
      if ident.resolved_declaration {
        if ident.resolved_declaration.expression && ident.resolved_declaration.expression.kind == .PROCEDURE_HEADER {
          header := cast(*Code_Procedure_Header) ident.resolved_declaration.expression;
          if header.body_or_null return header.body_or_null;
        }

        if ident.resolved_declaration.expression && ident.resolved_declaration.expression.kind == .PROCEDURE_BODY
          return cast(*Code_Procedure_Body) ident.resolved_declaration.expression;
      }

      // Some top-level declarations can be visited before ident.resolved_declaration is available.
      for procedure_bodies {
        if it.header.name == ident.name return it;
      }
    }
    case;
      return null;
  }
  return null;
}

resolve_shader_request_target_by_name :: (name: string, procedure_bodies: [] *Code_Procedure_Body) -> *Code_Procedure_Body {
  for procedure_bodies if it.header.name == name return it;
  return null;
}

collect_shader_requests_from_declaration :: (plugin: *Jai_To_Shader_Plugin, decl: *Code_Declaration, procedure_bodies: [] *Code_Procedure_Body) -> bool {
  if !decl return true;

  requested_languages: [..] Shader_Language;
  requested_glsl_targets: [..] GLSL_Target;
  pair_requested_languages: [..] Shader_Language;
  pair_requested_glsl_targets: [..] GLSL_Target;
  pair_fragment_names: [..] string;
  for decl.notes {
    language, glsl_target, is_shader_request := shader_request_name_to_language(it.text);
    if is_shader_request {
      array_add(*requested_languages, language);
      array_add(*requested_glsl_targets, glsl_target);
      continue;
    }

    pair_language, pair_glsl_target, fragment_name, pair_matched, pair_valid := parse_shader_pair_note(it.text);
    if !pair_matched continue;
    if !pair_valid {
      compiler_report("Jai Shader Transpiler: Invalid shader pair request note format. Use @shader_pair_to_metal(fragment_fn), @shader_pair_to_glsl(fragment_fn), or @shader_pair_to_vulkan(fragment_fn).", make_location(decl));
      continue;
    }
    array_add(*pair_requested_languages, pair_language);
    array_add(*pair_requested_glsl_targets, pair_glsl_target);
    array_add(*pair_fragment_names, fragment_name);
  }
  if requested_languages.count == 0 && pair_requested_languages.count == 0 return true;

  vertex_proc := resolve_shader_request_target(decl.expression, procedure_bodies);
  if !vertex_proc {
    // Declarations can typecheck before the target procedure body is available in early passes.
    return false;
  }
  vertex_lookup_name := vertex_proc.header.name;
  if decl.expression && decl.expression.kind == .IDENT {
    ident := cast(*Code_Ident) decl.expression;
    vertex_lookup_name = ident.name;
  }

  for requested_languages {
    language := it;
    glsl_target := requested_glsl_targets[it_index];
    if context_already_queued(plugin, language, vertex_proc, glsl_target) continue;
    ctx := create_shader_write_context(language, vertex_proc, glsl_target);
    entry_id := manifest_make_entry_id_single_from_parts(language, glsl_target, ctx.type, vertex_proc.header.name);
    if !shader_entry_id_is_selected(plugin.shader_entry_ids_filter, entry_id) continue;
    array_add(*plugin.currently_waiting_contexts, ctx);
    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := ifx language == .METAL then tprint("%_metal_string", vertex_proc.header.name) else tprint("%_string", vertex_proc.header.name);
      queue_lookup_entry(plugin, target_name, vertex_lookup_name, "", symbol_name);
    }
  }

  for pair_requested_languages {
    language := it;
    glsl_target := pair_requested_glsl_targets[it_index];
    fragment_name := pair_fragment_names[it_index];
    fragment_proc := resolve_shader_request_target_by_name(fragment_name, procedure_bodies);
    if !fragment_proc {
      // The fragment function can still appear later in typecheck order.
      return false;
    }

    vertex_is_valid   := proc_has_note(vertex_proc.header, "vertex_shader");
    fragment_is_valid := proc_has_note(fragment_proc.header, "fragment_shader");
    if !vertex_is_valid || !fragment_is_valid {
      compiler_report("Jai Shader Transpiler: shader_pair_to_* requires the declaration expression to resolve to a @vertex_shader and the note argument to resolve to a @fragment_shader.", make_location(decl));
      continue;
    }

    if pair_context_already_queued(plugin, language, vertex_proc, fragment_proc, glsl_target) continue;
    pair_name := ifx decl.name.count != 0 then decl.name else tprint("%_%", vertex_proc.header.name, fragment_proc.header.name);
    pair_ctx := Shader_Write_Pair_Context.{
      name = pair_name,
      language = language,
      glsl_target = glsl_target,
      vertex_fn = vertex_proc,
      fragment_fn = fragment_proc,
    };
    entry_id := manifest_make_entry_id_pair_from_parts(language, glsl_target, vertex_proc.header.name, fragment_proc.header.name);
    if !shader_entry_id_is_selected(plugin.shader_entry_ids_filter, entry_id) continue;
    array_add(*plugin.currently_waiting_pair_contexts, pair_ctx);
    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := ifx language == .METAL then tprint("%_metal_string", pair_name) else tprint("%_string", pair_name);
      queue_lookup_entry(plugin, target_name, vertex_lookup_name, fragment_name, symbol_name);
    }
  }
  return true;
}

shader_entry_id_is_selected :: (csv_filter: string, entry_id: string) -> bool {
  if csv_filter.count == 0 return true;
  if entry_id.count == 0 return false;

  i: s64 = 0;
  while i < csv_filter.count {
    while i < csv_filter.count && (csv_filter[i] == #char "," || csv_filter[i] == #char " " || csv_filter[i] == #char "\t" || csv_filter[i] == #char "\n" || csv_filter[i] == #char "\r") i += 1;
    if i >= csv_filter.count break;

    start := i;
    while i < csv_filter.count && csv_filter[i] != #char "," i += 1;
    token: string;
    token.data = csv_filter.data + start;
    token.count = i - start;
    token = trim_ascii_whitespace(token);
    if token.count != 0 && token == entry_id return true;

    if i < csv_filter.count && csv_filter[i] == #char "," i += 1;
  }

  return false;
}

Shader_Type :: IR_Shader_Kind;

Shader_Language :: enum {
  NONE;
  GLSL;
  HLSL;
  METAL;
}

GLSL_Target :: enum {
  OPENGL;
  VULKAN;
}

Shader_Function :: struct {
  prototype: *Code_Procedure_Header;
  name: string; // @Cleanup This doesn't have to be here
  code: string;
}

Shader_Write_Context :: struct {
  name: string;
  type: Shader_Type;
  language: Shader_Language;
  main_fn: *Code_Procedure_Body;
  functions: [..] Shader_Function;
  glsl_target: GLSL_Target;
  
  // TODO: enum_flags
  metal_use_jai_radians: bool;
  metal_use_jai_degrees: bool;
  metal_allow_fragcoord_from_position: bool;
}

Shader_Write_Pair_Context :: struct {
  name: string;
  language: Shader_Language;
  glsl_target: GLSL_Target;
  vertex_fn: *Code_Procedure_Body;
  fragment_fn: *Code_Procedure_Body;
}

member_is_stage_builtin :: (member: *Type_Info_Struct_Member) -> bool {
  auto_release_temp();
  
  builtin_string_fragments :: []string.{
    "position", "fragcoord", "fragdepth", "vertexid", "instanceid",
    "frontfacing", "pointsize", "sampleid", "samplemask",
  };

  for member.notes {
    normalized_note = replace(it, "_", "",, temp);
    to_lower_in_place(normalized_note);
    for fragment: builtin_string_fragment {
      if contains(normalized_note, fragment) {
        return true;
      }
    }
  }
  return false;
}

#scope_file

#import "Basic";
#import "Compiler";
PP :: #import "Program_Print";
#import "String";
#import "Math";
#import "Hash_Table";
#import "Thread";
#import "System";
#import "File";

#load "ir.jai";
#load "build_timings.jai";
#load "string_builder_util.jai";
#load "write_shader_manifest.jai";

proc_has_note :: (node: *Code_Procedure_Header, note: string) -> bool {
  for node.notes if it.text == note return true;
  return false;
}

create_shader_write_context :: (language: Shader_Language, proc: *Code_Procedure_Body, glsl_target: GLSL_Target = .OPENGL) -> Shader_Write_Context {
    shader_type: Shader_Type;
    if      proc_has_note(proc.header, "vertex_shader")    shader_type = .Vertex;
    else if proc_has_note(proc.header, "fragment_shader")  shader_type = .Fragment;
    else if proc_has_note(proc.header, "compute_shader")   shader_type = .Compute;
    else
      compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader", make_location(proc.header));
    
    return {
        name = proc.header.name,
        type = shader_type,
        language = language,
        main_fn = proc,
        glsl_target = glsl_target,
        metal_use_jai_radians = false,
        metal_use_jai_degrees = false,
        metal_allow_fragcoord_from_position = false,
    };
}


unpack_result :: (result: IR_Result($R)) -> (R, bool, IR_Diagnostic) {
    return result.value, result.ok, result.diag;
}

add_code :: (plugin: *Jai_To_Shader_Plugin, code: string, ctx := "") {
    add_build_string(code, plugin.workspace);
}
