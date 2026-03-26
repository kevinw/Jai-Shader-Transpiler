//
// Metaprogram plugin for converting Jai funcs marked with @vertex_shader @fragment_shader or @compute_shader to shaders.
// 
// Usage:
// 
// metal_bytes := get_transpiled(.METAL, pbr_vertex_main, pbr_fragment_main);
// 

offset_of :: ($T: Type, $member: string) -> int { // nocommit
    for type_info(T).members {
        if it.name == member return it.offset_in_bytes;
    }

    assert(false, "Type '%' does not have member '%'", T, member);
    return -1;
}

VERBOSE      :: false;
USE_SPIRV_OPT :: true;
WRITE_SPVASM_DEBUG :: false;
IR_INTERMEDIATE_DIR :: ".build/ir_intermediate"; // TODO: use get_build_options to determine a build-specific directory for this
DEBUG_OUTDIR :: ".generated_shaders"; // TODO: use get_build_options to determine a build-specific directory for this
JST_TOOL_VERSION_CACHE_DIR :: ".build/ir_tool_cache/tool_versions";
JST_TOOL_ARTIFACT_CACHE_DIR :: ".build/ir_tool_cache/artifacts";
JST_FINGERPRINT_FILE_CACHE_DIR :: ".build/ir_tool_cache/fingerprint_files";
MY_MODULE_NAME :: "Jai-Shader-Transpiler";

jst_pipeline_fingerprint_ready: bool;
jst_pipeline_fingerprint_cache: string;
jst_cache_summary_logged: bool;

JST_Cache_Stats :: struct {
  fingerprint_file_hits: s64;
  fingerprint_file_misses: s64;
  tool_version_hits: s64;
  tool_version_misses: s64;
  spirv_opt_hits: s64;
  spirv_opt_misses: s64;
  spirv_cross_hits: s64;
  spirv_cross_misses: s64;
  spirv_dis_hits: s64;
  spirv_dis_misses: s64;
}

jst_cache_stats: JST_Cache_Stats;

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
    manifest_app_name: string;
    
    // internal
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      emitted_symbol_names: [..] string;
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

jst_hash_u64_append_byte :: (h: *u64, b: u8) {
  h.* = (h.* ^ cast(u64) b) * 1099511628211;
}

jst_hash_u64_append_string :: (h: *u64, s: string) {
  for s jst_hash_u64_append_byte(h, it);
}

jst_trim_newlines :: (s: string) -> string {
  out := s;
  while out.count > 0 && (out[out.count-1] == #char "\n" || out[out.count-1] == #char "\r") out.count -= 1;
  return out;
}

jst_detect_module_root :: () -> string {
  cwd := get_working_directory();
  if contains(cwd, "modules/Jai-Shader-Transpiler") return ".";
  return "modules/Jai-Shader-Transpiler";
}

jst_collect_module_jai_files :: (module_root: string) -> [..] string {
  #import "File_Utilities";
  files: [..] string;
  visitor :: (info: *File_Visit_Info, user_data: *[..] string) {
      if ends_with(info.full_name, ".jai") {
          if contains(info.full_name, "/.") return; // TODO @Perf see why descend_into_directory isn't working on mac?
          array_add(user_data, copy_string(info.full_name));
      }
  }
  visit_files(module_root, true, *files, visitor);
  return files;
}

jst_tool_version_fingerprint_line :: (args: ..string) -> string {
  result, stdout, stderr, timeout_reached := Process.run_command(..args, capture_and_return_output=true, timeout_ms=3_000);
  if timeout_reached return tprint("timeout:%", args[0]);
  stdout = jst_trim_newlines(stdout);
  stderr = jst_trim_newlines(stderr);
  return tprint("tool=% type=% exit=% out=% err=%", args[0], result.type, result.exit_code, stdout, stderr);
}

jst_tool_version_cache_key :: (args: [] string) -> string {
  h: u64 = 1469598103934665603;
  jst_hash_u64_append_string(*h, "tool-version-v1");
  for args {
    jst_hash_u64_append_string(*h, it);
    jst_hash_u64_append_string(*h, "\n");
  }

  hex := sprint("%", formatInt(h, base=16));
  if hex.count == 0 return "0";
  return copy_string(hex);
}

jst_tool_version_fingerprint_line_cached :: (args: ..string) -> string {
  if args.count == 0 return "";

  make_directory_if_it_does_not_exist(JST_TOOL_VERSION_CACHE_DIR, recursive=true);
  cache_key := jst_tool_version_cache_key(args);
  cache_path := tprint("%/%_%.txt", JST_TOOL_VERSION_CACHE_DIR, args[0], cache_key);
  if FU.file_exists(cache_path) {
    cached, cached_ok := read_entire_file(cache_path);
    if cached_ok {
      jst_cache_stats.tool_version_hits += 1;
      return jst_trim_newlines(cached);
    }
  }

  jst_cache_stats.tool_version_misses += 1;
  line := jst_tool_version_fingerprint_line(..args);
  _ = write_entire_file(cache_path, line);
  return line;
}

jst_fingerprint_file_cache_key :: (path: string) -> string {
  h: u64 = 1469598103934665603;
  jst_hash_u64_append_string(*h, "fingerprint-file-v1");
  jst_hash_u64_append_string(*h, path);

  hex := sprint("%", formatInt(h, base=16));
  if hex.count == 0 return "0";
  return copy_string(hex);
}

jst_hash_string_u64_hex :: (s: string) -> string {
  h: u64 = 1469598103934665603;
  jst_hash_u64_append_string(*h, s);

  hex := sprint("%", formatInt(h, base=16));
  if hex.count == 0 return "0";
  return copy_string(hex);
}

jst_read_cached_module_file_hash :: (path: string) -> (string, bool) {
  modtime, size, stat_ok := FU.file_modtime_and_size(path);
  if !stat_ok return "", false;

  make_directory_if_it_does_not_exist(JST_FINGERPRINT_FILE_CACHE_DIR, recursive=true);
  cache_key := jst_fingerprint_file_cache_key(path);
  cache_path := tprint("%/%_cache.txt", JST_FINGERPRINT_FILE_CACHE_DIR, cache_key);
  stamp := tprint("%|%|%", modtime.high, modtime.low, size);

  if FU.file_exists(cache_path) {
    cached, cached_ok := read_entire_file(cache_path);
    if cached_ok {
      newline_index := find_index_from_left(cached, "\n");
      if newline_index >= 0 {
        cached_stamp := string.{newline_index, cached.data};
        if cached_stamp == stamp {
          hash_text := string.{cached.count - newline_index - 1, cached.data + newline_index + 1};
          hash_text = jst_trim_newlines(hash_text);
          if hash_text.count != 0 {
            jst_cache_stats.fingerprint_file_hits += 1;
            return copy_string(hash_text), true;
          }
        }
      }
    }
  }

  contents, read_ok := read_entire_file(path);
  if !read_ok return "", false;
  hash_text := jst_hash_string_u64_hex(contents);
  cache_text := tprint("%\n%", stamp, hash_text);
  _ = write_entire_file(cache_path, cache_text);
  jst_cache_stats.fingerprint_file_misses += 1;
  return hash_text, true;
}

jst_tool_artifact_cache_key :: (tool_name: string, tool_version: string, input_bytes: string, metadata: [] string) -> string {
  h: u64 = 1469598103934665603;
  jst_hash_u64_append_string(*h, "tool-artifact-v1");
  jst_hash_u64_append_string(*h, tool_name);
  jst_hash_u64_append_string(*h, "\n");
  jst_hash_u64_append_string(*h, tool_version);
  jst_hash_u64_append_string(*h, "\n");
  for metadata {
    jst_hash_u64_append_string(*h, it);
    jst_hash_u64_append_string(*h, "\n");
  }
  jst_hash_u64_append_string(*h, input_bytes);

  hex := sprint("%", formatInt(h, base=16));
  if hex.count == 0 return "0";
  return copy_string(hex);
}

jst_restore_cached_binary_artifact :: (cache_path: string, output_path: string) -> bool {
  if !FU.file_exists(cache_path) return false;
  data, ok := read_entire_file(cache_path);
  if !ok return false;
  return write_entire_file(output_path, data.data, data.count);
}

jst_restore_cached_text_artifact :: (cache_path: string, output_path: string) -> bool {
  if !FU.file_exists(cache_path) return false;
  data, ok := read_entire_file(cache_path);
  if !ok return false;
  return write_entire_file(output_path, data);
}

jst_store_cached_binary_artifact :: (source_path: string, cache_path: string) {
  data, ok := read_entire_file(source_path);
  if !ok return;
  _ = write_entire_file(cache_path, data.data, data.count);
}

jst_store_cached_text_artifact :: (source_path: string, cache_path: string) {
  data, ok := read_entire_file(source_path);
  if !ok return;
  _ = write_entire_file(cache_path, data);
}

jst_disassemble_spirv_binary_cached :: (input_spv: string, output_spvasm: string) -> bool {
  input_bytes, ok := read_entire_file(input_spv);
  if !ok return disassemble_spirv_binary(input_spv, output_spvasm);

  tool_version := jst_tool_version_fingerprint_line_cached("spirv-dis", "--version");
  metadata : [1] string = .["spirv-dis"];
  cache_key := jst_tool_artifact_cache_key("spirv-dis", tool_version, input_bytes, metadata);
  cache_dir := tprint("%/%", JST_TOOL_ARTIFACT_CACHE_DIR, "spirv-dis");
  make_directory_if_it_does_not_exist(cache_dir, recursive=true);
  cache_path := tprint("%/%_cached.spvasm", cache_dir, cache_key);
  if jst_restore_cached_text_artifact(cache_path, output_spvasm) {
    jst_cache_stats.spirv_dis_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_dis_misses += 1;
  if !disassemble_spirv_binary(input_spv, output_spvasm) return false;
  jst_store_cached_text_artifact(output_spvasm, cache_path);
  return true;
}

jst_optimize_spirv_binary_cached :: (input_spv: string, output_spv: string) -> bool {
  input_bytes, ok := read_entire_file(input_spv);
  if !ok return optimize_spirv_binary(input_spv, output_spv);

  tool_version := jst_tool_version_fingerprint_line_cached("spirv-opt", "--version");
  metadata : [1] string = .["-O"];
  cache_key := jst_tool_artifact_cache_key("spirv-opt", tool_version, input_bytes, metadata);
  cache_dir := tprint("%/%", JST_TOOL_ARTIFACT_CACHE_DIR, "spirv-opt");
  make_directory_if_it_does_not_exist(cache_dir, recursive=true);
  cache_path := tprint("%/%_cached.spv", cache_dir, cache_key);
  if jst_restore_cached_binary_artifact(cache_path, output_spv) {
    jst_cache_stats.spirv_opt_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_opt_misses += 1;
  if !optimize_spirv_binary(input_spv, output_spv) return false;
  jst_store_cached_binary_artifact(output_spv, cache_path);
  return true;
}

jst_emit_spirv_cross_target_source_cached :: (spv_path: string, entry_name: string, stage: IR_Shader_Kind, target: Toolchain_Target, output_path: string, use_metal_argument_buffers := false, source_entry_name := "main") -> bool {
  input_bytes, ok := read_entire_file(spv_path);
  if !ok return emit_spirv_cross_target_source(spv_path, entry_name, stage, target, output_path, use_metal_argument_buffers, source_entry_name=source_entry_name);

  tool_version := jst_tool_version_fingerprint_line_cached("spirv-cross", "--version");
  metadata : [5] string = .[
    tprint("target=%", target),
    tprint("stage=%", stage),
    tprint("entry=%", entry_name),
    tprint("source_entry=%", source_entry_name),
    tprint("argbuf=%", use_metal_argument_buffers),
  ];
  cache_key := jst_tool_artifact_cache_key("spirv-cross", tool_version, input_bytes, metadata);
  cache_dir := tprint("%/%", JST_TOOL_ARTIFACT_CACHE_DIR, "spirv-cross");
  make_directory_if_it_does_not_exist(cache_dir, recursive=true);
  ext := "glsl";
  if target == .METAL ext = "metal";
  cache_path := tprint("%/%_cached.%", cache_dir, cache_key, ext);
  if jst_restore_cached_text_artifact(cache_path, output_path) {
    jst_cache_stats.spirv_cross_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_cross_misses += 1;
  if !emit_spirv_cross_target_source(spv_path, entry_name, stage, target, output_path, use_metal_argument_buffers, source_entry_name=source_entry_name) return false;
  jst_store_cached_text_artifact(output_path, cache_path);
  return true;
}

jst_should_emit_spvasm_debug :: () -> bool {
  if WRITE_SPVASM_DEBUG return true;
  cwd := get_working_directory();
  if contains(cwd, "/headless_ir") return true;
  return false;
}

jst_log_cache_summary :: () {
  if jst_cache_summary_logged return;
  s := jst_cache_stats;
  total := s.fingerprint_file_hits + s.fingerprint_file_misses
         + s.tool_version_hits + s.tool_version_misses
         + s.spirv_opt_hits + s.spirv_opt_misses
         + s.spirv_cross_hits + s.spirv_cross_misses
         + s.spirv_dis_hits + s.spirv_dis_misses;
  if total == 0 return;
  jst_cache_summary_logged = true;
  log("JST cache: fingerprint h=% m=% | tool_version h=% m=% | spirv-opt h=% m=% | spirv-cross h=% m=% | spirv-dis h=% m=%",
      s.fingerprint_file_hits, s.fingerprint_file_misses,
      s.tool_version_hits, s.tool_version_misses,
      s.spirv_opt_hits, s.spirv_opt_misses,
      s.spirv_cross_hits, s.spirv_cross_misses,
      s.spirv_dis_hits, s.spirv_dis_misses);
}

jst_compute_pipeline_fingerprint :: () -> string {
  h: u64 = 1469598103934665603;
  jst_hash_u64_append_string(*h, "jai-shader-transpiler-pipeline-v2");
  jst_hash_u64_append_string(*h, tprint("USE_SPIRV_OPT=%", USE_SPIRV_OPT));

  module_root := jst_detect_module_root();
  files := jst_collect_module_jai_files(module_root);
  for files {
    content_hash, ok := jst_read_cached_module_file_hash(it);
    if !ok continue;
    jst_hash_u64_append_string(*h, "file:");
    jst_hash_u64_append_string(*h, it);
    jst_hash_u64_append_string(*h, "\n");
    jst_hash_u64_append_string(*h, content_hash);
    jst_hash_u64_append_string(*h, "\n");
  }

  jst_hash_u64_append_string(*h, jst_tool_version_fingerprint_line_cached("spirv-cross", "--version"));
  jst_hash_u64_append_string(*h, jst_tool_version_fingerprint_line_cached("spirv-opt", "--version"));
  jst_hash_u64_append_string(*h, jst_tool_version_fingerprint_line_cached("spirv-as", "--version"));
  jst_hash_u64_append_string(*h, jst_tool_version_fingerprint_line_cached("spirv-val", "--version"));

  hex := sprint("%", formatInt(h, base=16));
  if hex.count == 0 return "0";
  return copy_string(hex);
}

jst_pipeline_fingerprint :: () -> string {
  if !jst_pipeline_fingerprint_ready {
    jst_pipeline_fingerprint_cache = jst_compute_pipeline_fingerprint();
    jst_pipeline_fingerprint_ready = true;
  }
  return jst_pipeline_fingerprint_cache;
}

jst_use_fingerprinted_artifact_dirs :: () -> bool {
  cwd := get_working_directory();
  if contains(cwd, "/headless_ir") return false;
  return true;
}

jst_generated_dir :: () -> string {
  if !jst_use_fingerprinted_artifact_dirs() return DEBUG_OUTDIR;
  fp := jst_pipeline_fingerprint();
  if fp.count == 0 return DEBUG_OUTDIR;
  return tprint("%/%", DEBUG_OUTDIR, fp);
}

jst_ir_intermediate_dir :: () -> string {
  if !jst_use_fingerprinted_artifact_dirs() return IR_INTERMEDIATE_DIR;
  fp := jst_pipeline_fingerprint();
  if fp.count == 0 return IR_INTERMEDIATE_DIR;
  return tprint("%/%", IR_INTERMEDIATE_DIR, fp);
}

jst_mirror_to_legacy_intermediate_if_needed :: (path: string) {
  if !jst_use_fingerprinted_artifact_dirs() return;
  if path.count == 0 return;
  filename := path_filename(path);
  if filename.count == 0 return;
  data, ok := read_entire_file(path);
  if !ok return;
  make_directory_if_it_does_not_exist(IR_INTERMEDIATE_DIR, recursive=true);
  legacy_path := tprint("%/%", IR_INTERMEDIATE_DIR, filename);
  _ = write_entire_file(legacy_path, data);
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
    case "Transpiled_Target.METAL"; return "shader_to_metal",  "shader_pair_to_metal",  true,  true,  true;
    case ".HLSL";        return "shader_to_hlsl",   "",                      false, false, true;
    case "Transpiled_Target.HLSL"; return "shader_to_hlsl",   "",                      false, false, true;
    case ".OPENGL_GLSL"; return "shader_to_glsl",   "shader_pair_to_glsl",   true,  false, true;
    case "Transpiled_Target.OPENGL_GLSL"; return "shader_to_glsl",   "shader_pair_to_glsl",   true,  false, true;
    case ".VULKAN_GLSL"; return "shader_to_vulkan", "shader_pair_to_vulkan", true,  false, true;
    case "Transpiled_Target.VULKAN_GLSL"; return "shader_to_vulkan", "shader_pair_to_vulkan", true,  false, true;
  }
  return "", "", false, false, false;
}

canonical_transpiled_target_expr_string :: (expr: string) -> (string, bool) {
  if expr == {
    case ".METAL"; #through;
    case "Transpiled_Target.METAL"; return ".METAL", true;
    case ".HLSL"; #through;
    case "Transpiled_Target.HLSL"; return ".HLSL", true;
    case ".OPENGL_GLSL"; #through;
    case "Transpiled_Target.OPENGL_GLSL"; return ".OPENGL_GLSL", true;
    case ".VULKAN_GLSL"; #through;
    case "Transpiled_Target.VULKAN_GLSL"; return ".VULKAN_GLSL", true;
  }
  return "", false;
}

resolve_transpiled_target_expr_string :: (node: *Code_Node, depth: s64 = 0) -> (string, bool) #compile_time {
  if !node return "", false;
  if depth > 4 {
      log_error("hit depth max in resolve_transpiled_target_expr_string");
      return "", false;
  }

  expr := trim_ascii_whitespace(expression_to_source_string(node));
  if expr.count > 0 {
    _, _, _, _, ok := transpiled_target_from_expr_string(expr);
    if ok return expr, true;
  }

  if node.kind == .IDENT {
    ident := cast(*Code_Ident) node;
    if ident.resolved_declaration && ident.resolved_declaration.expression {
      nested_expr, nested_ok := resolve_transpiled_target_expr_string(ident.resolved_declaration.expression, depth + 1);
      return nested_expr, nested_ok;
    }
  }

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    if decl.expression {
      nested_expr, nested_ok := resolve_transpiled_target_expr_string(decl.expression, depth + 1);
      return nested_expr, nested_ok;
    }
  }

  return "", false;
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

Transpiled_Request_Info :: struct {
  request_name: string;
  source_symbol_name: string;
  function_constants_type_name: string;
  function_constant_info_name: string;
}

source_symbol_name_for_request :: (request_name: string) -> string {
  return tprint("%_source", request_name);
}

function_constants_type_name_for_request :: (request_name: string) -> string {
  return tprint("%_function_constants", generated_function_constant_base_name(request_name, ""));
}

function_constant_info_name_for_request :: (request_name: string) -> string {
  return tprint("%_function_constant_info", generated_function_constant_base_name(request_name, ""));
}

get_transpiled_request_info_from_call :: (call: Code, loc: Source_Code_Location) -> Transpiled_Request_Info #compile_time {
  return_fail :: (msg: string) #expand {
      compiler_report(tprint("Jai Shader Transpiler: %", msg), loc=loc);
      `return .{};
  }
  
  root := compiler_get_nodes(call);
  if root.kind != .PROCEDURE_CALL {
      return_fail("get_transpiled must be called directly (e.g. get_transpiled(.METAL, vertex_fn, fragment_fn)).");
  }

  pc := cast(*Code_Procedure_Call) root;
  if pc.arguments_unsorted.count != 2 && pc.arguments_unsorted.count != 3 {
      return_fail("get_transpiled expects 2 args (target, stage_fn) or 3 args (target, vertex_fn, fragment_fn).");
  }

  target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
  resolved_target_expr, resolved_target_ok := resolve_transpiled_target_expr_string(pc.arguments_unsorted[0].expression);
  target_parse_expr := ifx resolved_target_ok then resolved_target_expr else target_expr;
  canonical_target_expr, canonical_target_ok := canonical_transpiled_target_expr_string(target_parse_expr);
  single_note, pair_note, supports_pair, _, target_ok := transpiled_target_from_expr_string(canonical_target_expr);
  if !target_ok || !canonical_target_ok {
    return_fail("First argument to get_transpiled must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.");
  }
  target_ident := "";
  if canonical_target_expr == {
  case ".METAL";       target_ident = "metal";
  case ".HLSL";        target_ident = "hlsl";
  case ".OPENGL_GLSL"; target_ident = "opengl_glsl";
  case ".VULKAN_GLSL"; target_ident = "vulkan_glsl";
  case; return_fail("Failed to derive canonical target identifier for get_transpiled.");
  }

  shader_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
  if !shader_name {
    return_fail("get_transpiled shader arguments must be procedure identifiers.");
  }

  if pc.arguments_unsorted.count == 2 {
    request_name := tprint("transpiled_single_%_%", target_ident, shader_name);
    to_lower_in_place(request_name);
    key := tprint("single|%|%", single_note, shader_name);
    request_source := tprint("% :: %; @%\n", request_name, shader_name, single_note);
    ensure_get_transpiled_request_registered(key, request_source);
    return .{
      request_name = request_name,
      source_symbol_name = tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", canonical_target_expr, shader_name),
      function_constants_type_name = function_constants_type_name_for_request(request_name),
      function_constant_info_name = function_constant_info_name_for_request(request_name),
    };
  }

  if !supports_pair return_fail("get_transpiled target does not support paired graphics shaders for this backend.");

  fragment_name := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
  if !fragment_name return_fail("get_transpiled fragment argument must be a procedure identifier.");

  request_name := tprint("transpiled_pair_%_%_%", target_ident, shader_name, fragment_name);
  to_lower_in_place(request_name);
  key := tprint("pair|%|%|%", pair_note, shader_name, fragment_name);
  request_source := tprint("% :: %; @%(%)\n", request_name, shader_name, pair_note, fragment_name);
  
  #if 0 {
    log("-----");
    log("request_name:  %", request_name);
    log("pair_note:     %", pair_note);
    log("shader_name:   %", shader_name);
    log("fragment_name: %", fragment_name);
  }
  
  ensure_get_transpiled_request_registered(key, request_source);

  return .{
    request_name = request_name,
    source_symbol_name = tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", canonical_target_expr, shader_name, fragment_name),
    function_constants_type_name = function_constants_type_name_for_request(request_name),
    function_constant_info_name = function_constant_info_name_for_request(request_name),
  };
}


Shader_Meta :: struct {
    request_name: string;
    function_constants_type_name: string;
}

Transpiled_Shader :: struct {
    source: string;
    meta: Shader_Meta;
}

make_constants_code_string :: (using shader_meta: Shader_Meta) -> string {
    return tprint("%.{};", function_constants_type_name);
}

transpiled_shader_exprs_from_call :: (call: Code, loc: Source_Code_Location) -> (string, string, string) #compile_time {
    info := get_transpiled_request_info_from_call(call, loc);
    if info.request_name.count == 0 return "", "", "";

    source_expr := info.source_symbol_name;
    meta_expr := tprint("Shader_Meta.{request_name = \"%\", function_constants_type_name = \"%\"}", info.request_name, info.function_constants_type_name);
    constants_expr := tprint("%.{}", info.function_constants_type_name);
    return source_expr, meta_expr, constants_expr;
}

get_transpiled :: (
    target: Transpiled_Target, 
    args: ..Any, 
    call: Code = #caller_code, 
    loc: Source_Code_Location = #caller_location
) -> (shader_bytes: string, shader_meta: Shader_Meta) #expand {
    #insert #run,stallable -> string {
        source_expr, meta_expr, _ := transpiled_shader_exprs_from_call(call, loc);
        return tprint(#string END
G :: #import,file "%";
return %, %;
END, compute_path_to_shader_bucket_module(get_current_workspace()), source_expr, meta_expr);
    };
}

get_transpiled_shader :: (
    target: Transpiled_Target,
    args: ..Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) -> Transpiled_Shader #expand {
    #insert #run,stallable -> string {
        source_expr, meta_expr, _ := transpiled_shader_exprs_from_call(call, loc);
        return tprint(#string END
G :: #import,file "%";
return Transpiled_Shader.{source = %, meta = %};
END, compute_path_to_shader_bucket_module(get_current_workspace()), source_expr, meta_expr);
    };
}

get_default_function_constants :: (
    target: Transpiled_Target,
    args: ..Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) #expand {
    #insert #run,stallable -> string {
        _, _, constants_expr := transpiled_shader_exprs_from_call(call, loc);
        return tprint("%;", constants_expr);
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
          pair_source_symbol := source_symbol_name_from_pair_context(pair_ctx);
          if !generated_symbol_already_emitted(plugin, pair_source_symbol) {
            add_code(plugin, s, "waiting_pairs");
            mark_generated_symbol_emitted(plugin, pair_source_symbol);
          }
          emit_generated_function_constant_decl(plugin,
                                               generated_function_constant_base_name(pair_ctx.name, ""),
                                               pair_ctx.vertex_fn.header.name,
                                               pair_ctx.fragment_fn.header.name,
                                               pair_ctx.function_constants);

          if plugin.output_shaders {
            ext := tprint("%", pair_ctx.language);
            to_lower_in_place(ext);
            generated_dir := jst_generated_dir();
            make_directory_if_it_does_not_exist(generated_dir, recursive = true);
            filename := tprint("%/%.%", generated_dir, pair_ctx.name, ext);
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
            if ctx.language == .METAL {
              ctx.metal_output_source_path = copy_string(manifest_output_source_path(ctx.name, "METAL"));
              if ctx.metal_output_source_path.count != 0 {
                make_directory_if_it_does_not_exist(path_strip_filename(ctx.metal_output_source_path), recursive=true);
                if !write_entire_file(ctx.metal_output_source_path, source) {
                  compiler_report(tprint("Jai Shader Transpiler: failed to write Metal source '%'.", ctx.metal_output_source_path), make_location(ctx.main_fn.header));
                  continue;
                }
              }
              if ctx.type == .Vertex ctx.metal_vertex_entry_name = copy_string(it.entry_name);
              if ctx.type == .Fragment ctx.metal_fragment_entry_name = copy_string(it.entry_name);
              if ctx.type == .Compute {
                ctx.metal_compute_entry_name = copy_string(it.entry_name);
                if contains(source, "constant*") && contains(source, "[[buffer(0)]]") ctx.metal_compute_binding_mode = "ROOT_POINTER_STRUCT";
                else ctx.metal_compute_binding_mode = "DIRECT_ADDRESSES";
              }
            }

            source_symbol := source_symbol_name_from_context(ctx);
            if !generated_symbol_already_emitted(plugin, source_symbol) {
              s := tprint("% :: #string END\n%\nEND", source_symbol, source);
              add_code(plugin, s, "jobs");
              mark_generated_symbol_emitted(plugin, source_symbol);
            }
            emit_generated_function_constant_decl(plugin,
                                                 generated_function_constant_base_name(request_name_from_context(ctx), ""),
                                                 ctx.name,
                                                 "",
                                                 ctx.function_constants);
            if plugin.output_shaders {
              ext := tprint("%", ctx.language);
              to_lower_in_place(ext);
              generated_dir := jst_generated_dir();
              make_directory_if_it_does_not_exist(generated_dir, recursive = true);
              filename := tprint("%/%.%", generated_dir, ctx.name, ext);
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

        if !build_metal_artifacts_for_manifest_entries(plugin, workspace_root) {
          compiler_report("Jai Shader Transpiler: failed building Metal AIR/metallib artifacts.");
        }

        if plugin.manifest_entries.count > 0 emit_shader_reload_manifest(plugin);
        #if VERBOSE jst_log_cache_summary();

        emit_lookup_overloads(plugin, p.workspace);
      }
    }
    
    /*
    case .FILE;
        message_file := cast(*Message_File)message;
        log("FILE: % vs %", message_file.fully_pathed_filename, #file);
    */
    
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
      array_reset(*emitted_symbol_names);
      array_reset(*manifest_entries);
      did_emit_lookup_overloads = false;
      did_log_ir_pipeline = false;
      did_log_ir_limitations = false;
      jst_cache_stats = .{};
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

shader_function_constant_type :: enum {
    BOOL;
    U32;
    S32;
    FLOAT;
    FLOAT2;
    FLOAT3;
    FLOAT4;
}

shader_function_constant_info :: struct {
    name: string;
    index: u32;
    type: shader_function_constant_type;
    offset: s64;
}

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

request_target_ident_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == {
    case .METAL; return "_metal";
    case .HLSL; return "_hlsl";
    case .GLSL;
      if glsl_target == .VULKAN return "_vulkan_glsl";
      return "_opengl_glsl";
  }
  return "";
}

request_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  if !ctx return "";
  target_ident := request_target_ident_from_language(ctx.language, ctx.glsl_target);
  return tprint("transpiled_single_%_%", target_ident, ctx.name);
}

source_symbol_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  return source_symbol_name_for_request(request_name_from_context(ctx));
}

source_symbol_name_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  if !pair_ctx return "";
  return source_symbol_name_for_request(pair_ctx.name);
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

function_constant_decl_already_present :: (constants: [] IR_Function_Constant, decl: *Code_Declaration) -> bool {
  if !decl return false;
  for constants if it.declaration == decl return true;
  return false;
}

function_constant_spec_slot_count :: (type: IR_Function_Constant_Type) -> u32 {
  if type == {
    case .FLOAT2; return 2;
    case .FLOAT3; return 3;
    case .FLOAT4; return 4;
  }
  return 1;
}

assign_single_function_constant_spec_ids :: (shader: *IR_Shader) {
  if !shader return;
  next_spec_id: u32 = 0;
  for *shader.function_constants {
    it.spec_id = next_spec_id;
    next_spec_id += function_constant_spec_slot_count(it.type);
  }
}

assign_pair_function_constant_spec_ids :: (vertex: *IR_Vertex_Shader, fragment: *IR_Fragment_Shader, out_pair_constants: *[..] IR_Function_Constant) {
  array_reset(out_pair_constants);
  if vertex for vertex.function_constants if !function_constant_decl_already_present(out_pair_constants.*, it.declaration) array_add(out_pair_constants, it);
  if fragment for fragment.function_constants if !function_constant_decl_already_present(out_pair_constants.*, it.declaration) array_add(out_pair_constants, it);

  next_spec_id: u32 = 0;
  for i: 0..out_pair_constants.count-1 {
    out_pair_constants.*[i].spec_id = next_spec_id;
    next_spec_id += function_constant_spec_slot_count(out_pair_constants.*[i].type);
  }

  if vertex {
    for i: 0..vertex.function_constants.count-1 {
      fc := *vertex.function_constants[i];
      for pair_fc: out_pair_constants.* {
        if fc.declaration != pair_fc.declaration continue;
        fc.spec_id = pair_fc.spec_id;
        break;
      }
    }
  }
  if fragment {
    for i: 0..fragment.function_constants.count-1 {
      fc := *fragment.function_constants[i];
      for pair_fc: out_pair_constants.* {
        if fc.declaration != pair_fc.declaration continue;
        fc.spec_id = pair_fc.spec_id;
        break;
      }
    }
  }
}

generated_function_constant_base_name :: (request_name: string, kind_suffix: string) -> string {
  base := sanitize_identifier_component(request_name);
  to_lower_in_place(base);
  //while contains(base, "__") base = replace(base, "__", "_");
  if ends_with(base, "_main") {
    base.count -= 5;
  }
  if kind_suffix.count != 0 {
    suffix_text := tprint("_%", kind_suffix);
    if ends_with(base, suffix_text) return base;
    return tprint("%_%", base, kind_suffix);
  }
  return base;
}

emit_generated_function_constant_decl :: (plugin: *Jai_To_Shader_Plugin,
                                          base_name: string,
                                          primary_name: string,
                                          secondary_name: string,
                                          constants: [] IR_Function_Constant) {
  _ = primary_name;
  _ = secondary_name;

  struct_name := tprint("%_function_constants", base_name);
  info_name := tprint("%_function_constant_info", base_name);
  if generated_symbol_already_emitted(plugin, struct_name) return;

  sb: String_Builder;
  append(*sb, tprint("% :: struct {\n", struct_name));
  for constants {
    type_name := "bool";
    if #complete it.type == {
      case .BOOL;   type_name = "bool";
      case .U32;    type_name = "u32";
      case .S32;    type_name = "s32";
      case .FLOAT;  type_name = "float";
      case .FLOAT2; type_name = "Vector2";
      case .FLOAT3; type_name = "Vector3";
      case .FLOAT4; type_name = "Vector4";
    }
    append(*sb, tprint("  %: % = %;\n", it.name, type_name, it.default_value_text));
  }
  append(*sb, "}\n\n");
  append(*sb, tprint("% :: shader_function_constant_info.[\n", info_name));
  for constants {
    type_enum_str := tprint(".%", it.type);
    append(*sb, tprint("  .{name = \"%\", index = %, type = %, offset = #run offset_of(%, \"%\")},\n",
                       it.name, it.spec_id, type_enum_str, struct_name, it.name));
  }
  append(*sb, "];\n");

  code := builder_to_string(*sb);
  #if VERBOSE log("----\n%\n----", code);

  add_code(plugin, code, tprint("function_constants_%", base_name));
  mark_generated_symbol_emitted(plugin, struct_name);
  mark_generated_symbol_emitted(plugin, info_name);
}

ir_output_path_from_context :: (ctx: *Shader_Write_Context) -> string {
  return tprint("%/%.%", jst_generated_dir(), ctx.name, ir_output_ext_from_context(ctx));
}

ir_output_path_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  return tprint("%/%.metal", jst_generated_dir(), pair_ctx.name);
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
  source_entry_name: string;
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

  spv_binary: [] u8;
  spv_ok := false;
  spv_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;

  if ctx.type == .Vertex {
    vert_result := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_vertex, lowered, lowered_diag := unpack_result(vert_result);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_vertex);
    entry_name = ir_vertex.entry_name;
    vert_spv_res := to_spv_binary(*ir_vertex);
    spv_binary, spv_ok, spv_diag = unpack_result(vert_spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    frag_lower_res := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_fragment, lowered, lowered_diag := unpack_result(frag_lower_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_fragment);
    entry_name = ir_fragment.entry_name;
    frag_spv_res := to_spv_binary(*ir_fragment);
    spv_binary, spv_ok, spv_diag = unpack_result(frag_spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    lower_compute_res := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_compute, lowered, lowered_diag := unpack_result(lower_compute_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_compute);
    entry_name = ir_compute.entry_name;
    compute_spv_res := to_spv_binary(*ir_compute);
    spv_binary, spv_ok, spv_diag = unpack_result(compute_spv_res);
  }

  if entry_name.count == 0
      return_err("SPIR-V backend: empty entry name.");
  source_entry_name := entry_name;
  if ctx.language == .METAL {
    if ctx.type == .Compute entry_name = tprint("%_ComputeMain", ctx.name);
  }

  build_dir := jst_ir_intermediate_dir();
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  stage_short := ir_stage_short_from_context(ctx);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";

  job.ctx = ctx;
  job.validate_before_opt = false;
  job.stage = ctx.type;
  job.target = target;
  job.entry_name = copy_string(entry_name);
  job.source_entry_name = copy_string(source_entry_name);
  job.use_metal_argument_buffers = use_metal_argument_buffers;
  job.spvasm_path = sprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  job.spv_path = sprint("%/%_%.spv", build_dir, ctx.name, stage_short);
  job.spv_opt_path = sprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short);
  job.output_path = sprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);
  job.ok = false;
  job.error_message = "";

  if !spv_ok {
    if spv_diag.message.count == 0 spv_diag.message = tprint("SPIR-V binary backend: failed to emit SPIR-V for '%'.", ctx.name);
    if !spv_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spv_diag.location = make_location(ctx.main_fn.header);
      spv_diag.has_location = true;
    }
    return false, spv_diag;
  }

  if !write_entire_file(job.spv_path, spv_binary.data, spv_binary.count) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V binary '%'.", job.spv_path);
    if spv_binary.data free(spv_binary.data);
    return false, diag;
  }
  if spv_binary.data free(spv_binary.data);
  jst_mirror_to_legacy_intermediate_if_needed(job.spv_path);

  return true, diag;
}

run_spirv_external_single_job :: (job: *SPV_External_Single_Job) -> bool {
  assert(job != null);
  if job.validate_before_opt {
    if !validate_spirv_binary(job.spv_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
  }

  if USE_SPIRV_OPT {
    if !jst_optimize_spirv_binary_cached(job.spv_path, job.spv_opt_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
    jst_mirror_to_legacy_intermediate_if_needed(job.spv_opt_path);
  } else {
    job.spv_opt_path = job.spv_path;
  }

  if !validate_spirv_binary(job.spv_opt_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }

  if jst_should_emit_spvasm_debug() {
    if !jst_disassemble_spirv_binary_cached(job.spv_path, job.spvasm_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-dis failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
    jst_mirror_to_legacy_intermediate_if_needed(job.spvasm_path);
  }

  if !jst_emit_spirv_cross_target_source_cached(job.spv_opt_path, job.entry_name, job.stage, job.target, job.output_path, job.use_metal_argument_buffers, source_entry_name=job.source_entry_name) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }
  jst_mirror_to_legacy_intermediate_if_needed(job.output_path);

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

Metal_Air_Compile_Job :: struct {
  source_path: string;
  air_path: string;
  ok: bool;
  error_message: string;
}

run_metal_air_compile_job :: (job: *Metal_Air_Compile_Job) -> bool {
  assert(job != null);
  if job.source_path.count == 0 || job.air_path.count == 0 {
    job.error_message = copy_string("Metal AIR compile job missing source/output path.");
    return false;
  }
  result, stdout, stderr, timeout_reached := Process.run_command(
    "xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", job.source_path, "-o", job.air_path,
    capture_and_return_output=true, timeout_ms=30_000);
  if timeout_reached {
    job.error_message = copy_string(tprint("xcrun metal timed out for '%'.", job.source_path));
    return false;
  }
  if result.type == .FAILED_TO_LAUNCH {
    job.error_message = copy_string("Failed to launch xcrun metal.");
    return false;
  }
  if result.type != .EXITED || result.exit_code != 0 {
    job.error_message = copy_string(tprint("xcrun metal failed for '%':\n%\n%", job.source_path, stdout, stderr));
    return false;
  }
  return true;
}

metal_air_compile_worker_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
  _ = group;
  _ = thread;
  job := cast(*Metal_Air_Compile_Job) work;
  job.ok = run_metal_air_compile_job(job);
  return .CONTINUE;
}

run_metal_air_compile_jobs_parallel :: (jobs: [] Metal_Air_Compile_Job) -> bool {
  if jobs.count == 0 return true;
  cpus := get_number_of_processors();
  if cpus < 1 cpus = 1;
  worker_count := min(max(cpus - 1, 1), cast(s32) jobs.count);
  tg: Thread_Group;
  init(*tg, worker_count, metal_air_compile_worker_proc);
  tg.logging = false;
  tg.name = "JTS-Metal-AIR";
  start(*tg);
  defer shutdown(*tg);

  for *jobs add_work(*tg, it);

  completed := 0;
  while completed < jobs.count {
    done := get_completed_work(*tg);
    completed += done.count;
    if completed < jobs.count sleep_milliseconds(1);
  }

  for jobs {
    if it.ok continue;
    if it.error_message.count != 0 log_error("%", it.error_message);
    else log_error("xcrun metal failed for '%'.", it.source_path);
    return false;
  }
  return true;
}

sanitize_workspace_name_for_artifacts :: (workspace_name: string) -> string {
  out := copy_string(workspace_name);
  if out.count == 0 return "workspace";
  for out {
    if it == {
      case #char " "; #through;
      case #char "/"; #through;
      case #char "\\"; #through;
      case #char ":";
        out[it_index] = "_";
    }
  }
  return out;
}

metallib_stem_from_request_name :: (request_name: string) -> string {
  if request_name.count == 0 return "";
  pair_prefix := "transpiled_pair_metal_";
  legacy_pair_prefix := "transpiled_pair__metal_";
  if begins_with(request_name, pair_prefix) || begins_with(request_name, legacy_pair_prefix) {
    prefix := ifx begins_with(request_name, pair_prefix) then pair_prefix else legacy_pair_prefix;
    rest: string = {request_name.count - prefix.count, request_name.data + prefix.count};
    marker := "_vertex_main_";
    at, found := find_substring_index_local(rest, marker);
    if found && at > 0 {
      out: string = {at, rest.data};
      return copy_string(out);
    }
    return copy_string(rest);
  }

  single_prefix := "transpiled_single_metal_";
  legacy_single_prefix := "transpiled_single__metal_";
  if begins_with(request_name, single_prefix) || begins_with(request_name, legacy_single_prefix) {
    prefix := ifx begins_with(request_name, single_prefix) then single_prefix else legacy_single_prefix;
    rest: string = {request_name.count - prefix.count, request_name.data + prefix.count};
    marker := "_compute_main";
    at, found := find_substring_index_local(rest, marker);
    if found && at > 0 {
      out: string = {at, rest.data};
      return copy_string(out);
    }
    return copy_string(rest);
  }

  return "";
}

stable_metallib_workspace_name :: (plugin: *Jai_To_Shader_Plugin) -> string {
  if !plugin return "workspace";
  for plugin.manifest_entries {
    if it.target != "METAL" continue;
    stem := metallib_stem_from_request_name(it.request_name);
    if stem.count != 0 return sanitize_workspace_name_for_artifacts(stem);
  }
  return sanitize_workspace_name_for_artifacts(copy_string(get_name(plugin.workspace),, temp));
}

find_substring_index_local :: (haystack: string, needle: string) -> (s64, bool) {
  if needle.count == 0 || haystack.count < needle.count return 0, false;
  max_start := haystack.count - needle.count;
  for i: 0..max_start {
    matched := true;
    for j: 0..needle.count-1 {
      if haystack[i + j] != needle[j] {
        matched = false;
        break;
      }
    }
    if matched return i, true;
  }
  return 0, false;
}

is_absolute_path_local :: (path: string) -> bool {
  if path.count == 0 return false;
  if path[0] == #char "/" return true;
  if path.count >= 3 && path[1] == #char ":" && (path[2] == #char "/" || path[2] == #char "\\") return true;
  return false;
}

string_array_contains_local :: (haystack: [] string, needle: string) -> bool {
  for haystack if it == needle return true;
  return false;
}

link_metallib_from_air_files :: (air_paths: [] string, metallib_path: string) -> bool {
  if air_paths.count == 0 || metallib_path.count == 0 return false;
  args: [..] string;
  args.allocator = temp;
  array_add(*args, "xcrun", "-sdk", "macosx", "metallib");
  for air_paths array_add(*args, it);
  array_add(*args, "-o", metallib_path);

  result, stdout, stderr, timeout_reached := Process.run_command(..args, capture_and_return_output=true, timeout_ms=30_000);
  if timeout_reached {
    log_error("xcrun metallib timed out for '%'.", metallib_path);
    return false;
  }
  if result.type == .FAILED_TO_LAUNCH {
    log_error("Failed to launch xcrun metallib.");
    return false;
  }
  if result.type != .EXITED || result.exit_code != 0 {
    if stdout.count != 0 log("%", stdout);
    if stderr.count != 0 log_error("%", stderr);
    log_error("xcrun metallib failed for '%'.", metallib_path);
    return false;
  }
  return true;
}

build_metal_artifacts_for_manifest_entries :: (plugin: *Jai_To_Shader_Plugin, workspace_root: string) -> bool {
  if !plugin return true;
  if contains(workspace_root, "modules/Jai-Shader-Transpiler") {
    // Keep transpiler examples/tests on source-only behavior for now.
    return true;
  }

  workspace_name := stable_metallib_workspace_name(plugin);
  generated_dir := jst_generated_dir();
  make_directory_if_it_does_not_exist(generated_dir, recursive=true);
  metallib_rel_path := tprint("%/%_app.metallib", generated_dir, workspace_name);

  jobs: [..] Metal_Air_Compile_Job;
  air_paths: [..] string;
  seen_sources: [..] string;
  seen_sources.allocator = temp;

  for *plugin.manifest_entries {
    if it.target != "METAL" continue;
    if it.output_source_path.count == 0 {
      log_error("Jai Shader Transpiler: missing Metal source path for entry '%'.", it.entry_id);
      return false;
    }

    source_abs := it.output_source_path;
    if !is_absolute_path_local(source_abs) source_abs = tprint("%/%", workspace_root, source_abs);
    _, source_exists := read_entire_file(source_abs);
    if !source_exists {
      log_error("Jai Shader Transpiler: Metal source missing for entry '%': %", it.entry_id, source_abs);
      return false;
    }

    air_rel_path := tprint("%.air", it.output_source_path);
    air_abs_path := air_rel_path;
    if !is_absolute_path_local(air_abs_path) air_abs_path = tprint("%/%", workspace_root, air_abs_path);
    make_directory_if_it_does_not_exist(path_strip_filename(air_abs_path), recursive=true);

    it.output_air_path = copy_string(air_rel_path);
    it.output_metallib_path = copy_string(metallib_rel_path);

    if !string_array_contains_local(seen_sources, source_abs) {
      array_add(*seen_sources, source_abs);
      array_add(*jobs, .{
        source_path = source_abs,
        air_path = air_abs_path,
      });
      array_add(*air_paths, air_abs_path);
    }
  }

  if jobs.count == 0 return true;
  if !run_metal_air_compile_jobs_parallel(jobs) return false;

  metallib_abs_path := metallib_rel_path;
  if !is_absolute_path_local(metallib_abs_path) metallib_abs_path = tprint("%/%", workspace_root, metallib_abs_path);
  make_directory_if_it_does_not_exist(path_strip_filename(metallib_abs_path), recursive=true);
  if !link_metallib_from_air_files(air_paths, metallib_abs_path) return false;

  return true;
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

  spv_binary: [] u8;
  spv_ok := false;
  spv_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;
  if ctx.type == .Vertex {
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    assign_single_function_constant_spec_ids(*ir_vertex);
    normalized, normalize_diag := normalize_vertex_ir(*ir_vertex);
    if !normalized return "", "", false, normalize_diag;
    ctx.function_constants = ir_vertex.function_constants;
    entry_name = ir_vertex.entry_name;
    spv_res := to_spv_binary(*ir_vertex);
    spv_binary, spv_ok, spv_diag = unpack_result(spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    assign_single_function_constant_spec_ids(*ir_fragment);
    normalized, normalize_diag := normalize_shader(*ir_fragment);
    if !normalized return "", "", false, normalize_diag;
    ctx.function_constants = ir_fragment.function_constants;
    entry_name = ir_fragment.entry_name;
    spv_res := to_spv_binary(*ir_fragment);
    spv_binary, spv_ok, spv_diag = unpack_result(spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered return "", "", false, lowered_diag;
    assign_single_function_constant_spec_ids(*ir_compute);
    normalized, normalize_diag := normalize_compute_ir(*ir_compute);
    if !normalized return "", "", false, normalize_diag;
    ctx.function_constants = ir_compute.function_constants;
    entry_name = ir_compute.entry_name;
    spv_res := to_spv_binary(*ir_compute);
    spv_binary, spv_ok, spv_diag = unpack_result(spv_res);
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

  build_dir := jst_ir_intermediate_dir();
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

  spvasm_path := tprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  if !spv_ok {
    if ctx.type == .Compute {
      if spv_diag.message.count == 0 spv_diag.message = tprint("SPIR-V binary backend: failed to emit SPIR-V for '%'.", ctx.name);
    } else {
      if spv_diag.message.count == 0 spv_diag.message = tprint("SPIR-V binary backend: failed to translate SPIR-V assembly for '%'.", ctx.name);
    }
    if !spv_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spv_diag.location = make_location(ctx.main_fn.header);
      spv_diag.has_location = true;
    }
    return "", "", false, spv_diag;
  }
  if !write_entire_file(spv_path, spv_binary.data, spv_binary.count) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V binary '%'.", spv_path);
    if spv_binary.data free(spv_binary.data);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if spv_binary.data free(spv_binary.data);
  jst_mirror_to_legacy_intermediate_if_needed(spv_path);

  spv_for_target := spv_path;
  if !jst_optimize_spirv_binary_cached(spv_path, spv_opt_path) {
    diag.message = tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", ctx.name, spv_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(spv_opt_path);
  spv_for_target = spv_opt_path;

  if !validate_spirv_binary(spv_for_target) {
    diag.message = tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if jst_should_emit_spvasm_debug() {
    if !jst_disassemble_spirv_binary_cached(spv_path, spvasm_path) {
      diag.message = tprint("SPIR-V backend: spirv-dis failed for '%'. SPIR-V: %", ctx.name, spv_path);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
    jst_mirror_to_legacy_intermediate_if_needed(spvasm_path);
  }

  if !jst_emit_spirv_cross_target_source_cached(spv_for_target, entry_name, ctx.type, target, output_path, use_metal_argument_buffers, source_entry_name=entry_name) {
    diag.message = tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(output_path);

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

  symbol_name := source_symbol_name_from_context(ctx);
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
  assign_single_function_constant_spec_ids(*ir_vertex);
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
  assign_single_function_constant_spec_ids(*ir_fragment);
  normalize_shader(*ir_fragment);
  assign_pair_function_constant_spec_ids(*ir_vertex, *ir_fragment, *pair_ctx.function_constants);

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
  emit_ir_graphics_pair_to_spirv_binary_branch :: (vertex: IR_Vertex_Shader, fragment: IR_Fragment_Shader) -> (vertex_spv: []u8, fragment_spv: []u8, ok: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    assert(vertex.entry_name.count != 0);
    assert(fragment.entry_name.count != 0);
    
    vert_spv_res := to_spv_binary(*vertex);
    vertex_spv, vertex_ok, vertex_diag := unpack_result(vert_spv_res);
    if !vertex_ok return .[], .[], false, vertex_diag;
    
    frag_spv_res := to_spv_binary(*fragment);
    fragment_spv, fragment_ok, fragment_diag := unpack_result(frag_spv_res);
    if !fragment_ok return .[], .[], false, fragment_diag;
    
    return vertex_spv, fragment_spv, true, diag;
  }

  vertex_spv_binary, fragment_spv_binary, pair_spvasm_ok, pair_spvasm_diag := emit_ir_graphics_pair_to_spirv_binary_branch(ir_vertex, ir_fragment);
  if !pair_spvasm_ok {
    if !pair_spvasm_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      pair_spvasm_diag.location = make_location(pair_ctx.vertex_fn.header);
      pair_spvasm_diag.has_location = true;
    }
    return "", false, pair_spvasm_diag;
  }
  build_dir := jst_ir_intermediate_dir();
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
  metal_vertex_entry_name := tprint("%_VertexMain", pair_ctx.name);
  metal_fragment_entry_name := tprint("%_FragmentMain", pair_ctx.name);
  if !write_entire_file(vertex_spv_path, vertex_spv_binary.data, vertex_spv_binary.count) || !write_entire_file(fragment_spv_path, fragment_spv_binary.data, fragment_spv_binary.count) {
    diag.message = "SPIR-V backend: failed writing pair SPIR-V binaries.";
    if vertex_spv_binary.data free(vertex_spv_binary.data);
    if fragment_spv_binary.data free(fragment_spv_binary.data);
    return "", false, diag;
  }
  if vertex_spv_binary.data free(vertex_spv_binary.data);
  if fragment_spv_binary.data free(fragment_spv_binary.data);
  jst_mirror_to_legacy_intermediate_if_needed(vertex_spv_path);
  jst_mirror_to_legacy_intermediate_if_needed(fragment_spv_path);
  if !link_spirv_binaries(.[vertex_spv_path, fragment_spv_path], pair_spv_path) {
    diag.message = "SPIR-V backend: spirv-link failed for pair module.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(pair_spv_path);
  if !jst_optimize_spirv_binary_cached(pair_spv_path, pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for pair module.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(pair_opt_spv_path);
  if !validate_spirv_binary(pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for pair module.";
    return "", false, diag;
  }
  if jst_should_emit_spvasm_debug() {
    if !jst_disassemble_spirv_binary_cached(pair_opt_spv_path, pair_spvasm_path) {
      diag.message = "SPIR-V backend: spirv-dis failed for optimized pair module.";
      return "", false, diag;
    }
    jst_mirror_to_legacy_intermediate_if_needed(pair_spvasm_path);
  }
  if !jst_emit_spirv_cross_target_source_cached(pair_opt_spv_path, metal_vertex_entry_name, .Vertex, .METAL, vertex_output_path, use_metal_argument_buffers, source_entry_name=ir_vertex.entry_name) {
    diag.message = "SPIR-V backend: pair vertex spirv-cross failed.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(vertex_output_path);
  if !jst_emit_spirv_cross_target_source_cached(pair_opt_spv_path, metal_fragment_entry_name, .Fragment, .METAL, fragment_output_path, use_metal_argument_buffers, source_entry_name=ir_fragment.entry_name) {
    diag.message = "SPIR-V backend: pair fragment spirv-cross failed.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(fragment_output_path);

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

  pair_ctx.metal_vertex_entry_name = copy_string(metal_vertex_entry_name);
  pair_ctx.metal_fragment_entry_name = copy_string(metal_fragment_entry_name);
  pair_ctx.metal_output_source_path = copy_string(manifest_output_source_path(pair_ctx.name, "METAL"));
  if pair_ctx.metal_output_source_path.count != 0 {
    make_directory_if_it_does_not_exist(path_strip_filename(pair_ctx.metal_output_source_path), recursive=true);
    if !write_entire_file(pair_ctx.metal_output_source_path, merged_source) {
      diag.message = tprint("SPIR-V backend: failed writing pair source '%'.", pair_ctx.metal_output_source_path);
      if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
        diag.location = make_location(pair_ctx.vertex_fn.header);
        diag.has_location = true;
      }
      return "", false, diag;
    }
  }

  decl := tprint("% :: #string END\n%\nEND", source_symbol_name_from_pair_context(pair_ctx), merged_source);
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
  if plugin.did_emit_lookup_overloads {
    plugin.did_emit_lookup_overloads = false;
    emit_lookup_overloads(plugin, plugin.workspace);
  }
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
      request_name := tprint("transpiled_single_%_%", request_target_ident_from_language(language, glsl_target), ctx.name);
      to_lower_in_place(request_name);
      symbol_name := source_symbol_name_for_request(request_name);
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
      symbol_name := source_symbol_name_for_request(pair_name);
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
  metal_output_source_path: string;
  metal_output_air_path: string;
  metal_output_metallib_path: string;
  metal_vertex_entry_name: string;
  metal_fragment_entry_name: string;
  metal_compute_entry_name: string;
  metal_compute_binding_mode: string;
  function_constants: [..] IR_Function_Constant;
}

Shader_Write_Pair_Context :: struct {
  name: string;
  language: Shader_Language;
  glsl_target: GLSL_Target;
  vertex_fn: *Code_Procedure_Body;
  fragment_fn: *Code_Procedure_Body;
  metal_output_source_path: string;
  metal_output_air_path: string;
  metal_output_metallib_path: string;
  metal_vertex_entry_name: string;
  metal_fragment_entry_name: string;
  function_constants: [..] IR_Function_Constant;
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
FU :: #import "File_Utilities";
Process :: #import "Process";

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
      compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader or @compute_shader", make_location(proc.header));
    
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

generated_symbol_already_emitted :: (plugin: *Jai_To_Shader_Plugin, name: string) -> bool {
  for plugin.emitted_symbol_names if it == name return true;
  return false;
}

mark_generated_symbol_emitted :: (plugin: *Jai_To_Shader_Plugin, name: string) {
  if name.count == 0 return;
  if generated_symbol_already_emitted(plugin, name) return;
  array_add(*plugin.emitted_symbol_names, copy_string(name));
}
