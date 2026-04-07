#scope_file
Process_metal :: #import "Process";
#scope_export

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
  result, stdout, stderr, timeout_reached := Process_metal.run_command(
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

stable_metal_bundle_name :: (plugin: *Jai_To_Shader_Plugin) -> string {
  if !plugin return "workspace";
  if plugin.manifest_app_name.count != 0 return sanitize_workspace_name_for_artifacts(plugin.manifest_app_name);
  return sanitize_workspace_name_for_artifacts(copy_string(get_name(plugin.workspace),, temp));
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

  result, stdout, stderr, timeout_reached := Process_metal.run_command(..args, capture_and_return_output=true, timeout_ms=30_000);
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

strip_generated_comment_preamble_local :: (source: string) -> string {
  if !begins_with(source, "// Generated from ") return source;
  cursor: s64 = 0;
  while cursor < source.count && source[cursor] != #char "\n" cursor += 1;
  while cursor < source.count && (source[cursor] == #char "\n" || source[cursor] == #char "\r") cursor += 1;
  out: string;
  out.data = source.data + cursor;
  out.count = source.count - cursor;
  return out;
}

build_metal_source_bundle_for_manifest_entries :: (plugin: *Jai_To_Shader_Plugin, workspace_root: string, out_bundle_rel_path: *string) -> bool {
  assert(plugin != null && out_bundle_rel_path != null);

  bundle_name := stable_metal_bundle_name(plugin);
  generated_dir := jst_generated_dir();
  make_directory_if_it_does_not_exist(generated_dir, recursive=true);
  bundle_rel_path := tprint("%/%_bundle.metal", generated_dir, bundle_name);
  bundle_abs_path := bundle_rel_path;
  if !is_absolute_path_local(bundle_abs_path) bundle_abs_path = tprint("%/%", workspace_root, bundle_rel_path);

  unique_source_paths: [..] string;
  unique_source_paths.allocator = temp;

  for plugin.manifest_entries {
    if it.target != "METAL" continue;
    if it.output_source_path.count == 0 {
      compiler_report(tprint("Jai Shader Transpiler: missing Metal source path for entry '%'.", it.entry_id));
      return false;
    }

    source_abs := it.output_source_path;
    if !is_absolute_path_local(source_abs) source_abs = tprint("%/%", workspace_root, source_abs);
    if !string_array_contains_local(unique_source_paths, source_abs) array_add(*unique_source_paths, source_abs);
  }

  if unique_source_paths.count == 0 return true;

  source_texts: [..] string;
  source_texts.allocator = temp;
  for unique_source_paths {
    source_text, ok := read_entire_file(it);
    if !ok {
      compiler_report(tprint("Jai Shader Transpiler: Metal source missing for bundle input '%'.", it));
      return false;
    }
    array_add(*source_texts, strip_generated_comment_preamble_local(source_text));
  }

  merged_source := ir_merge_metal_bundle_sources(source_texts);

  merged_source = ir_metal_enable_unsafe_runtime_array_indexing(merged_source);
  app_label := ifx plugin.manifest_app_name.count != 0 then plugin.manifest_app_name else bundle_name;
  merged_source = ir_prepend_generated_comment(merged_source, tprint("app shader bundle %", app_label), ir_pipeline_label_spirv(.METAL));

  make_directory_if_it_does_not_exist(path_strip_filename(bundle_abs_path), recursive=true);
  if !write_entire_file(bundle_abs_path, merged_source) {
    compiler_report(tprint("Jai Shader Transpiler: failed writing Metal bundle '%'.", bundle_abs_path));
    return false;
  }

  out_bundle_rel_path.* = copy_string(bundle_rel_path);
  jst_log_shader_output_path(bundle_rel_path, "final app shader bundle");
  return true;
}

build_metal_artifacts_for_manifest_entries :: (plugin: *Jai_To_Shader_Plugin, workspace_root: string) -> bool {
  if !plugin return true;
  if contains(workspace_root, "modules/Jai-Shader-Transpiler") {
    // Keep transpiler examples/tests on source-only behavior for now.
    return true;
  }

  bundle_name := stable_metal_bundle_name(plugin);
  generated_dir := jst_generated_dir();
  make_directory_if_it_does_not_exist(generated_dir, recursive=true);
  metallib_rel_path := tprint("%/%_bundle.metallib", generated_dir, bundle_name);
  bundle_rel_path: string;
  if !build_metal_source_bundle_for_manifest_entries(plugin, workspace_root, *bundle_rel_path) return false;
  if bundle_rel_path.count == 0 return true;

  bundle_abs_path := bundle_rel_path;
  if !is_absolute_path_local(bundle_abs_path) bundle_abs_path = tprint("%/%", workspace_root, bundle_abs_path);
  bundle_air_rel_path := tprint("%.air", bundle_rel_path);
  bundle_air_abs_path := bundle_air_rel_path;
  if !is_absolute_path_local(bundle_air_abs_path) bundle_air_abs_path = tprint("%/%", workspace_root, bundle_air_rel_path);
  make_directory_if_it_does_not_exist(path_strip_filename(bundle_air_abs_path), recursive=true);

  compile_job := Metal_Air_Compile_Job.{
    source_path = bundle_abs_path,
    air_path = bundle_air_abs_path,
  };
  if !run_metal_air_compile_job(*compile_job) {
    if compile_job.error_message.count != 0 compiler_report(compile_job.error_message);
    else compiler_report(tprint("Jai Shader Transpiler: failed compiling Metal AIR for '%'.", bundle_abs_path));
    return false;
  }

  metallib_abs_path := metallib_rel_path;
  if !is_absolute_path_local(metallib_abs_path) metallib_abs_path = tprint("%/%", workspace_root, metallib_abs_path);
  make_directory_if_it_does_not_exist(path_strip_filename(metallib_abs_path), recursive=true);
  if !link_metallib_from_air_files(.[bundle_air_abs_path], metallib_abs_path) {
    compiler_report(tprint("Jai Shader Transpiler: failed linking metallib '%'.", metallib_abs_path));
    return false;
  }

  for *plugin.manifest_entries {
    if it.target != "METAL" continue;
    it.output_source_path = copy_string(bundle_rel_path);
    it.output_air_path = copy_string(bundle_air_rel_path);
    it.output_metallib_path = copy_string(metallib_rel_path);
  }

  return true;
}
