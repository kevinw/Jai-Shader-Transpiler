#scope_file
FU_cache :: #import "File_Utilities";
Process_cache :: #import "Process";
#scope_export

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
  result, stdout, stderr, timeout_reached := Process_cache.run_command(..args, capture_and_return_output=true, timeout_ms=3_000);
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
  if FU_cache.file_exists(cache_path) {
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
  modtime, size, stat_ok := FU_cache.file_modtime_and_size(path);
  if !stat_ok return "", false;

  make_directory_if_it_does_not_exist(JST_FINGERPRINT_FILE_CACHE_DIR, recursive=true);
  cache_key := jst_fingerprint_file_cache_key(path);
  cache_path := tprint("%/%_cache.txt", JST_FINGERPRINT_FILE_CACHE_DIR, cache_key);
  stamp := tprint("%|%|%", modtime.high, modtime.low, size);

  if FU_cache.file_exists(cache_path) {
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

jst_restore_cached_artifact :: (cache_path: string, output_path: string) -> bool {
  if !FU_cache.file_exists(cache_path) return false;
  data, ok := read_entire_file(cache_path);
  if !ok return false;
  return write_entire_file(output_path, data.data, data.count);
}

jst_store_cached_artifact :: (source_path: string, cache_path: string) {
  data, ok := read_entire_file(source_path);
  if !ok return;
  _ = write_entire_file(cache_path, data.data, data.count);
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
  if jst_restore_cached_artifact(cache_path, output_spvasm) {
    jst_cache_stats.spirv_dis_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_dis_misses += 1;
  if !disassemble_spirv_binary(input_spv, output_spvasm) return false;
  jst_store_cached_artifact(output_spvasm, cache_path);
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
  if jst_restore_cached_artifact(cache_path, output_spv) {
    jst_cache_stats.spirv_opt_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_opt_misses += 1;
  if !optimize_spirv_binary(input_spv, output_spv) return false;
  jst_store_cached_artifact(output_spv, cache_path);
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
  if jst_restore_cached_artifact(cache_path, output_path) {
    jst_cache_stats.spirv_cross_hits += 1;
    return true;
  }

  jst_cache_stats.spirv_cross_misses += 1;
  if !emit_spirv_cross_target_source(spv_path, entry_name, stage, target, output_path, use_metal_argument_buffers, source_entry_name=source_entry_name) return false;
  jst_store_cached_artifact(output_path, cache_path);
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
