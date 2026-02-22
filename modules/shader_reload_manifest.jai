Shader_Reload_Manifest_Entry :: struct {
    entry_id: string;
    request_name: string;
    output_source_path: string;
    shader_kind: string;
    stage: string;
    target: string;
    primary_name: string;
    secondary_name: string;
    signature: string;
    signature_hash: string;
    dependencies: [..] string;
}

Shader_Reload_Manifest :: struct {
    loaded: bool;
    source_path: string;
    backing_text: string;
    version: s64;
    declared_entry_count: s64;
    entries: [..] Shader_Reload_Manifest_Entry;
    global_dependencies: [..] string;
}

Shader_Reload_Dependency_State :: struct {
    rel_path: string;
    resolved_path: string;
    modtime: Apollo_Time;
    size: s64;
    exists: bool;
    content_hash: u64;
}

Shader_Path_Context :: struct {
    workspace_root: string;
    generated_dir: string;
    manifest_latest_path: string;
    build_working_dir: string;
}

PEEL_WORKSPACE_SENTINEL :: ".peel_workspace";

Shader_Reload_Watcher :: struct {
    enabled: bool;
    app_source_file: string;
    poll_every_frames: s64;
    last_poll_frame: s64;
    manifest: Shader_Reload_Manifest;
    paths: Shader_Path_Context;
    dependency_states: [..] Shader_Reload_Dependency_State;
    last_changed_entry_ids_csv: string;
    last_build_ok: bool;
}

shader_reload_manifest_reset :: (manifest: *Shader_Reload_Manifest) {
    manifest.loaded = false;
    manifest.source_path = "";
    manifest.backing_text = "";
    manifest.version = 0;
    manifest.declared_entry_count = 0;
    array_reset(*manifest.entries);
    array_reset(*manifest.global_dependencies);
}

shader_reload_manifest_load :: (manifest: *Shader_Reload_Manifest, path: string) -> bool {
    text, ok := read_entire_file(path);
    if !ok return false;

    shader_reload_manifest_reset(manifest);
    manifest.source_path = copy_string(path);
    manifest.backing_text = text;

    in_entry := false;
    current_entry: Shader_Reload_Manifest_Entry;

    i: s64 = 0;
    while i < text.count {
        start := i;
        while i < text.count && text[i] != #char "\n" i += 1;
        line: string;
        line.data = text.data + start;
        line.count = i - start;
        if i < text.count && text[i] == #char "\n" i += 1;

        line = manifest_trim_ascii_whitespace(line);
        if line.count == 0 continue;
        if line == "entry_begin" {
            in_entry = true;
            current_entry = .{};
            continue;
        }
        if line == "entry_end" {
            if in_entry {
                if current_entry.entry_id.count == 0 || current_entry.request_name.count == 0 || current_entry.output_source_path.count == 0 {
                    log_error("Invalid shader reload manifest entry in '%': required fields missing (entry_id/request_name/output_source_path).", path);
                    return false;
                }
                array_add(*manifest.entries, current_entry);
            }
            in_entry = false;
            continue;
        }

        key, value, kv_ok := manifest_parse_key_value(line);
        if !kv_ok continue;

        if !in_entry {
            if key == "version" {
                manifest.version = manifest_parse_s64(value);
            } else if key == "entry_count" {
                manifest.declared_entry_count = manifest_parse_s64(value);
            } else if key == "global_dependency" {
                array_add(*manifest.global_dependencies, value);
            }
            continue;
        }

        if key == "entry_id" {
            current_entry.entry_id = value;
        } else if key == "request_name" {
            current_entry.request_name = value;
        } else if key == "output_source_path" {
            current_entry.output_source_path = value;
        } else if key == "shader_kind" {
            current_entry.shader_kind = value;
        } else if key == "stage" {
            current_entry.stage = value;
        } else if key == "target" {
            current_entry.target = value;
        } else if key == "primary_name" {
            current_entry.primary_name = value;
        } else if key == "secondary_name" {
            current_entry.secondary_name = value;
        } else if key == "signature" {
            current_entry.signature = value;
        } else if key == "signature_hash" {
            current_entry.signature_hash = value;
        } else if key == "dependency" {
            array_add(*current_entry.dependencies, value);
        }
    }

    if manifest.version < 2 {
        log_error("Unsupported shader reload manifest version % in '%'. Expected version 2+.", manifest.version, path);
        return false;
    }

    manifest.loaded = true;
    return true;
}

shader_reload_manifest_load_latest :: (manifest: *Shader_Reload_Manifest) -> bool {
    return shader_reload_manifest_load(manifest, ".generated_shaders/shader_reload_manifest_latest.txt");
}

shader_reload_manifest_load_with_context :: (manifest: *Shader_Reload_Manifest, using paths: *Shader_Path_Context) -> bool {
    candidate_paths: [..] string;
    candidate_paths.allocator = temp;
    if manifest_latest_path.count != 0 array_add(*candidate_paths, manifest_latest_path);
    if generated_dir.count != 0 array_add(*candidate_paths, tprint("%/shader_reload_manifest_latest.txt", generated_dir));

    for candidate_paths {
        verbose_log("manifest candidate=%", it);
        _, _, exists := File_Utilities.file_modtime_and_size(it);
        if !exists continue;
        if shader_reload_manifest_load(manifest, it) {
            verbose_log("manifest loaded=%", it);
            return true;
        }
    }
    verbose_log("manifest load failed (root=% generated=%).", workspace_root, generated_dir);
    return false;
}

shader_reload_manifest_load_auto :: (manifest: *Shader_Reload_Manifest) -> bool {
    paths := make_path_context_auto("");
    return shader_reload_manifest_load_with_context(manifest, *paths);
}

shader_reload_manifest_find_entry :: (manifest: *Shader_Reload_Manifest, entry_id: string) -> *Shader_Reload_Manifest_Entry {
    for *manifest.entries {
        if it.entry_id == entry_id return it;
    }
    return null;
}

shader_reload_manifest_find_entry_source_for_manifest :: (manifest: *Shader_Reload_Manifest, entry: *Shader_Reload_Manifest_Entry, using paths: *Shader_Path_Context) -> (string, bool) {
    if !entry || entry.output_source_path.count == 0 return "", false;

    path := entry.output_source_path;
    if !manifest_path_is_absolute(path) {
        if workspace_root.count != 0 {
            path = String.path_join(workspace_root, path);
        } else if manifest && manifest.source_path.count != 0 {
            manifest_dir := String.path_strip_filename(manifest.source_path);
            if manifest_dir.count != 0 path = String.path_join(manifest_dir, path);
        }
    }

    verbose_log("source canonical entry=% path=%", entry.entry_id, path);
    _, _, ok := File_Utilities.file_modtime_and_size(path);
    if ok {
        verbose_log("source resolved entry=% path=%", entry.entry_id, path);
        return path, true;
    }
    verbose_log("source missing entry=% path=%", entry.entry_id, path);
    return "", false;
}

shader_reload_manifest_find_entry_source_auto :: (entry: *Shader_Reload_Manifest_Entry) -> (string, bool) {
    paths := make_path_context_auto("");
    return shader_reload_manifest_find_entry_source_for_manifest(null, entry, *paths);
}

shader_reload_watcher_init_auto :: (watcher: *Shader_Reload_Watcher, app_source_file: string, poll_every_frames: s64 = 15, enabled_by_default: bool = false) -> bool {
    watcher.* = .{};
    watcher.app_source_file = copy_string(app_source_file);
    watcher.paths = make_path_context_auto(app_source_file);
    watcher.poll_every_frames = max(1, poll_every_frames);
    watcher.last_poll_frame = -1;
    watcher.last_build_ok = true;

    watcher.enabled = enabled_by_default;

    enabled_int, enabled_set := manifest_try_parse_env_int("PEEL_SHADER_RELOAD");
    if enabled_set watcher.enabled = enabled_int > 0;
    if !watcher.enabled return false;

    if !shader_reload_manifest_load_with_context(*watcher.manifest, *watcher.paths) {
        log_error("SHADER_RELOAD failed to load manifest.");
        watcher.enabled = false;
        return false;
    }

    watcher_refresh_dependency_baseline(watcher);
    log("SHADER_RELOAD enabled app=% manifest=% entries=% deps=% poll_every=%",
        watcher.app_source_file,
        watcher.manifest.source_path,
        watcher.manifest.entries.count,
        watcher.dependency_states.count,
        watcher.poll_every_frames);
    log("SHADER_RELOAD paths root=% generated=%", watcher.paths.workspace_root, watcher.paths.generated_dir);
    return true;
}

shader_reload_watcher_poll_and_rebuild :: (watcher: *Shader_Reload_Watcher, frame_num: s64) -> (bool, bool) {
    changed_entry_ids_csv, has_changes := shader_reload_watcher_poll_changed_entry_ids_csv(watcher, frame_num);
    if !has_changes return false, true;
    return true, shader_reload_watcher_rebuild_entry_ids(watcher, changed_entry_ids_csv);
}

shader_reload_watcher_poll_changed_entry_ids_csv :: (watcher: *Shader_Reload_Watcher, frame_num: s64) -> (string, bool) {
    if !watcher.enabled || !watcher.manifest.loaded return "", false;
    if frame_num <= 0 return "", false;
    if watcher.last_poll_frame >= 0 && frame_num - watcher.last_poll_frame < watcher.poll_every_frames return "", false;
    watcher.last_poll_frame = frame_num;

    changed_paths: [..] string;
    changed_paths.allocator = temp;

    for *watcher.dependency_states {
        modtime, size, exists := File_Utilities.file_modtime_and_size(it.resolved_path);
        changed := false;
        if exists != it.exists {
            changed = true;
        } else if exists && (modtime != it.modtime || size != it.size) {
            changed = true;
        } else if exists {
            // Some file systems/edit flows can keep identical size and coarse modtime across quick edits.
            // Fall back to content hash so repeated shader edits are not missed.
            content_hash, hash_ok := manifest_try_hash_file(it.resolved_path);
            if hash_ok && content_hash != it.content_hash {
                changed = true;
                it.content_hash = content_hash;
            }
        }
        if changed {
            array_add(*changed_paths, it.rel_path);
            it.modtime = modtime;
            it.size = size;
            it.exists = exists;
            if !exists {
                it.content_hash = 0;
            } else {
                content_hash, hash_ok := manifest_try_hash_file(it.resolved_path);
                if hash_ok it.content_hash = content_hash;
                else it.content_hash = 0;
            }
        }
    }

    if changed_paths.count == 0 return "", false;

    changed_entry_ids_csv := manifest_collect_changed_entry_ids_csv(*watcher.manifest, changed_paths);
    if changed_entry_ids_csv.count == 0 return "", false;
    watcher.last_changed_entry_ids_csv = changed_entry_ids_csv;
    verbose_log("changed_paths=%", String.join(..changed_paths, separator = ","));
    verbose_log("changed_entry_ids=%", changed_entry_ids_csv);
    return changed_entry_ids_csv, true;
}

shader_reload_watcher_rebuild_entry_ids :: (watcher: *Shader_Reload_Watcher, changed_entry_ids_csv: string, timeout_ms: s32 = 120000) -> bool {
    if changed_entry_ids_csv.count == 0 return true;

    ok := shader_reload_build_entry_ids_with_context(*watcher.paths, watcher.app_source_file, changed_entry_ids_csv, timeout_ms);
    watcher.last_build_ok = ok;
    if !ok return false;

    _ = shader_reload_manifest_load_with_context(*watcher.manifest, *watcher.paths);
    watcher_refresh_dependency_baseline(watcher);
    log("SHADER_RELOAD build succeeded app=% ids=%", watcher.app_source_file, changed_entry_ids_csv);
    return true;
}

shader_reload_build_entry_ids_with_context :: (using paths: *Shader_Path_Context, app_source_file: string, changed_entry_ids_csv: string, timeout_ms: s32 = 120000) -> bool {
    if app_source_file.count == 0 || changed_entry_ids_csv.count == 0 return false;

    verbose_log("build start app=% ids=% cwd=%", app_source_file, changed_entry_ids_csv, build_working_dir);
    process_result, stdout, stderr, timeout := Process.run_command(
        "jai",
        "build.jai",
        "-",
        "-shader_only",
        "-shader_entry_ids",
        changed_entry_ids_csv,
        app_source_file,
        working_directory = build_working_dir,
        capture_and_return_output = true,
        timeout_ms = timeout_ms);

    if timeout {
        log_error("SHADER_RELOAD build timed out app=% ids=%", app_source_file, changed_entry_ids_csv);
        return false;
    }

    if process_result.type != .EXITED || process_result.exit_code != 0 {
        if stdout.count > 0 write_strings("SHADER_RELOAD stdout:\n", stdout, "\n", to_standard_error = true);
        if stderr.count > 0 write_strings("SHADER_RELOAD stderr:\n", stderr, "\n", to_standard_error = true);
        log_error("SHADER_RELOAD build failed app=% ids=%", app_source_file, changed_entry_ids_csv);
        return false;
    }

    verbose_log("build ok app=% ids=%", app_source_file, changed_entry_ids_csv);
    return true;
}

shader_reload_build_entry_ids :: (app_source_file: string, changed_entry_ids_csv: string, timeout_ms: s32 = 120000) -> bool {
    paths := make_path_context_auto(app_source_file);
    return shader_reload_build_entry_ids_with_context(*paths, app_source_file, changed_entry_ids_csv, timeout_ms);
}

shader_reload_watcher_refresh_baseline :: (watcher: *Shader_Reload_Watcher) {
    watcher_refresh_dependency_baseline(watcher);
}

#scope_file

watcher_refresh_dependency_baseline :: (watcher: *Shader_Reload_Watcher) {
    array_reset(*watcher.dependency_states);

    for watcher.manifest.global_dependencies {
        watcher_add_dependency_state(watcher, *watcher.dependency_states, it);
    }
    for watcher.manifest.entries {
        for it.dependencies {
            watcher_add_dependency_state(watcher, *watcher.dependency_states, it);
        }
    }
}

watcher_add_dependency_state :: (watcher: *Shader_Reload_Watcher, states: *[..] Shader_Reload_Dependency_State, rel_path: string) {
    for states.* if it.rel_path == rel_path return;

    resolved := manifest_resolve_workspace_relative_path(watcher, rel_path);
    modtime, size, exists := File_Utilities.file_modtime_and_size(resolved);
    content_hash: u64 = 0;
    if exists {
        h, hash_ok := manifest_try_hash_file(resolved);
        if hash_ok content_hash = h;
    }
    verbose_log("dependency baseline rel=% resolved=% exists=% size=%", rel_path, resolved, exists, size);
    array_add(states, .{
        rel_path = copy_string(rel_path),
        resolved_path = copy_string(resolved),
        modtime = modtime,
        size = size,
        exists = exists,
        content_hash = content_hash,
    });
}

manifest_resolve_workspace_relative_path :: (watcher: *Shader_Reload_Watcher, rel_path: string) -> string {
    if rel_path.count == 0 return "";
    if manifest_path_is_absolute(rel_path) return rel_path;

    if watcher && watcher.paths.workspace_root.count != 0 {
        rooted := String.path_join(watcher.paths.workspace_root, rel_path);
        _, _, ok := File_Utilities.file_modtime_and_size(rooted);
        if ok return rooted;
        // Keep deterministic rooted path even if missing (for create/delete tracking).
        return rooted;
    }

    return rel_path;
}

manifest_collect_changed_entry_ids_csv :: (manifest: *Shader_Reload_Manifest, changed_paths: [] string) -> string {
    global_changed := false;
    for changed_paths {
        if manifest_string_in_list(manifest.global_dependencies, it) {
            global_changed = true;
            break;
        }
    }

    entry_ids: [..] string;
    entry_ids.allocator = temp;
    if global_changed {
        for manifest.entries if it.entry_id.count != 0 array_add(*entry_ids, it.entry_id);
    } else {
        for entry: manifest.entries {
            entry_changed := false;
            for changed_path: changed_paths {
                if manifest_string_in_list(entry.dependencies, changed_path) {
                    entry_changed = true;
                    break;
                }
            }
            if entry_changed && entry.entry_id.count != 0 array_add(*entry_ids, entry.entry_id);
        }
    }

    sb: String_Builder;
    for entry_ids {
        if it_index != 0 append(*sb, ",");
        append(*sb, it);
    }
    return builder_to_string(*sb);
}

manifest_string_in_list :: (list: [] string, value: string) -> bool {
    for list if it == value return true;
    return false;
}

make_path_context_auto :: (app_source_file: string) -> Shader_Path_Context {
    out: Shader_Path_Context;
    cwd := get_working_directory();

    env_root := manifest_try_parse_env_path("PEEL_WORKSPACE_ROOT");
    if env_root.count != 0 && manifest_is_workspace_root(env_root) {
        out.workspace_root = copy_string(env_root);
    }

    if out.workspace_root.count == 0 {
        out.workspace_root = copy_string(manifest_find_workspace_root_auto(cwd, app_source_file));
    }
    if out.workspace_root.count == 0 {
        // Last-resort compatibility fallback.
        out.workspace_root = ".";
    }

    out.generated_dir = copy_string(String.path_join(out.workspace_root, ".generated_shaders"));
    out.manifest_latest_path = copy_string(String.path_join(out.generated_dir, "shader_reload_manifest_latest.txt"));
    out.build_working_dir = copy_string(out.workspace_root);
    verbose_log("context cwd=% app=% root=% generated=%", cwd, app_source_file, out.workspace_root, out.generated_dir);
    return out;
}

manifest_find_build_working_directory :: () -> string {
    paths := make_path_context_auto("");
    return paths.build_working_dir;
}

manifest_find_workspace_root_auto :: (cwd: string, app_source_file: string) -> string {
    if manifest_is_workspace_root(cwd) return cwd;

    if app_source_file.count != 0 {
        app_path := app_source_file;
        if !manifest_path_is_absolute(app_path) {
            app_path = String.path_join(cwd, app_path);
        }
        base := String.path_strip_filename(app_path);
        root := manifest_walk_up_for_workspace_root(base);
        if root.count != 0 return root;
    }

    root := manifest_walk_up_for_workspace_root(cwd);
    if root.count != 0 return root;

    return cwd;
}

manifest_walk_up_for_workspace_root :: (start_path: string) -> string {
    path := start_path;
    for 0..16 {
        if path.count == 0 break;
        if manifest_is_workspace_root(path) return path;
        next := manifest_parent_dir(path);
        if next == path break;
        path = next;
    }
    return "";
}

manifest_parent_dir :: (path: string) -> string {
    if path.count == 0 return "";
    trimmed := path;
    while trimmed.count > 1 {
        c := trimmed[trimmed.count - 1];
        if c != #char "/" && c != #char "\\" break;
        trimmed.count -= 1;
    }
    parent := String.path_strip_filename(trimmed);
    if parent.count == 0 return "";
    while parent.count > 1 {
        c := parent[parent.count - 1];
        if c != #char "/" && c != #char "\\" break;
        parent.count -= 1;
    }
    return copy_string(parent);
}

manifest_is_workspace_root :: (path: string) -> bool {
    if path.count == 0 return false;
    marker := String.path_join(path, PEEL_WORKSPACE_SENTINEL);
    _, _, exists := File_Utilities.file_modtime_and_size(marker);
    return exists;
}

manifest_path_is_absolute :: (path: string) -> bool {
    if path.count == 0 return false;
    c0 := path[0];
    if c0 == #char "/" || c0 == #char "\\" return true;
    if path.count >= 2 {
        c1 := path[1];
        if c1 == #char ":" return true;
    }
    return false;
}

manifest_parse_key_value :: (line: string) -> (string, string, bool) {
    split_index: s64 = -1;
    for line {
        if it == #char " " {
            split_index = it_index;
            break;
        }
    }
    if split_index <= 0 || split_index >= line.count - 1 return "", "", false;

    key: string;
    key.data = line.data;
    key.count = split_index;

    value: string;
    value.data = line.data + split_index + 1;
    value.count = line.count - split_index - 1;
    value = manifest_trim_ascii_whitespace(value);

    return key, value, true;
}

manifest_target_ext :: (target: string) -> string {
    if target == "METAL" return "metal";
    if target == "HLSL" return "hlsl";
    if target == "OPENGL_GLSL" return "glsl";
    if target == "VULKAN_GLSL" return "glsl";
    return "";
}

manifest_parse_s64 :: (value: string) -> s64 {
    parsed, ok, _ := String.string_to_int(value);
    if !ok return 0;
    return cast(s64) parsed;
}

manifest_try_parse_env_int :: (name: string) -> (s64, bool) {
    value_c := getenv(temp_c_string(name));
    if !value_c return 0, false;
    value_str := to_string(value_c, c_style_strlen(value_c));
    parsed, ok, _ := String.string_to_int(value_str);
    if !ok {
        log_error("Invalid %='%'. Expected integer.", name, value_str);
        return 0, false;
    }
    return cast(s64) parsed, true;
}

manifest_try_parse_env_path :: (name: string) -> string {
    value_c := getenv(temp_c_string(name));
    if !value_c return "";
    value_str := to_string(value_c, c_style_strlen(value_c));
    if value_str.count == 0 return "";
    return copy_string(value_str);
}

manifest_try_hash_file :: (path: string) -> (u64, bool) {
    data, ok := read_entire_file(path);
    if !ok return 0, false;
    if data.count == 0 return 0, true;
    return fnv1a_hash(data.data, data.count), true;
}

#if VERBOSE {
    verbose_log :: (format: string, args: ..Any) {
        prefixed := tprint("SHADER_RELOAD %", format);
        log(prefixed, ..args);
    }
} else {
    verbose_log :: (format: string, args: ..Any) {
        _ = format;
        _ = args;
    }
}

manifest_trim_ascii_whitespace :: (s: string) -> string {
    if s.count == 0 return s;

    start: s64 = 0;
    while start < s.count {
        c := s[start];
        if c != #char " " && c != #char "\t" && c != #char "\n" && c != #char "\r" break;
        start += 1;
    }

    end := s.count;
    while end > start {
        c := s[end - 1];
        if c != #char " " && c != #char "\t" && c != #char "\n" && c != #char "\r" break;
        end -= 1;
    }

    out: string;
    out.data = s.data + start;
    out.count = end - start;
    return out;
}

#import "Basic";
#import "File";
File_Utilities :: #import "File_Utilities";
Process :: #import "Process";
String :: #import "String";
using Hash;
Hash :: #import "Hash";
using,only(getenv) POSIX :: #import "POSIX";

VERBOSE :: false;
