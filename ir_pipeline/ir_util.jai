#scope_export 

shader_name_from_call_arg :: (arg: *Code_Node) -> string {
  if !arg return "";
  if arg.kind == {
    case .IDENT;
      ident := cast(*Code_Ident) arg;
      return ident.name;
    case .PROCEDURE_BODY;
      proc := cast(*Code_Procedure_Body) arg;
      return proc.header.name;
    case .PROCEDURE_HEADER;
      header := cast(*Code_Procedure_Header) arg;
      return header.name;
  } 

  expr := trim_ascii_whitespace(expression_to_source_string(arg));
  if expr.count == 0 return "";

  end := expr.count - 1;
  while end >= 0 {
    ch := expr[end];
    if (ch >= #char "a" && ch <= #char "z") || (ch >= #char "A" && ch <= #char "Z") || (ch >= #char "0" && ch <= #char "9") || ch == #char "_" {
      break;
    }
    end -= 1;
  }
  if end < 0 return "";

  start := end;
  while start >= 0 {
    ch := expr[start];
    if !((ch >= #char "a" && ch <= #char "z") || (ch >= #char "A" && ch <= #char "Z") || (ch >= #char "0" && ch <= #char "9") || ch == #char "_") {
      break;
    }
    start -= 1;
  }
  start += 1;

  name: string;
  name.data = expr.data + start;
  name.count = end - start + 1;
  if name.count == 0 return "";
  return name;
} @jdll_export 



ir_metal_split_top_level_decls :: (source: string, out_preamble: *string, out_decls: *[..] string) {
  assert(out_preamble != null);
  assert(out_decls != null);

  preamble_end := ir_metal_find_preamble_end(source);
  preamble: string;
  preamble.data = source.data;
  preamble.count = preamble_end;
  out_preamble.* = preamble;

  i := preamble_end;
  while i < source.count {
    while i < source.count {
      ch := source[i];
      if ch != #char " " && ch != #char "\t" && ch != #char "\r" && ch != #char "\n" break;
      i += 1;
    }
    if i >= source.count break;

    start := i;
    brace_depth: s64 = 0;
    paren_depth: s64 = 0;
    saw_block := false;
    ended := false;

    while i < source.count {
      ch := source[i];
      if ch == #char "(" paren_depth += 1;
      if ch == #char ")" && paren_depth > 0 paren_depth -= 1;
      if ch == #char "{" {
        brace_depth += 1;
        saw_block = true;
      }
      if ch == #char "}" && brace_depth > 0 {
        brace_depth -= 1;
        if brace_depth == 0 && saw_block {
          cursor := i + 1;
          while cursor < source.count && (source[cursor] == #char " " || source[cursor] == #char "\t" || source[cursor] == #char "\r" || source[cursor] == #char "\n") {
            cursor += 1;
          }
          // Struct/enum declarations terminate with `};`, function definitions at `}`.
          if cursor >= source.count || source[cursor] != #char ";" {
            i += 1;
            ended = true;
            break;
          }
        }
      }
      if ch == #char ";" && brace_depth == 0 && paren_depth == 0 {
        i += 1;
        ended = true;
        break;
      }
      i += 1;
    }

    if !ended && i >= source.count {
      // Accept trailing declaration-like chunk at EOF.
    }

    decl: string;
    decl.data = source.data + start;
    decl.count = i - start;
    if decl.count > 0 array_add(out_decls, copy_string(decl));
  }
} @jdll_export 

ir_merge_metal_pair_sources :: (vertex_source: string, fragment_source: string) -> string {
  preamble_v: string;
  preamble_f: string;
  decls_v: [..] string;
  decls_f: [..] string;
  ir_metal_split_top_level_decls(vertex_source, *preamble_v, *decls_v);
  ir_metal_split_top_level_decls(fragment_source, *preamble_f, *decls_f);

  sb: String_Builder;
  if preamble_v.count != 0      a(*sb, preamble_v);
  else if preamble_f.count != 0 a(*sb, preamble_f);

  seen: Table(string, bool);
  selected_decls: [..] string;
  selected_type_decl_index: Table(string, s64);

  for decls_v {
    decl := it;
    key := ir_metal_compact_decl_key(decl);
    if key.count == 0 continue;
    found, _ := table_find(*seen, key);
    if found continue;

    is_forward := ir_metal_is_forward_type_decl(decl);
    type_name, type_name_ok := ir_metal_declared_type_name(decl);
    if type_name_ok && !is_forward {
      type_found, existing_index := table_find(*selected_type_decl_index, type_name);
      if type_found {
        selected_decls[existing_index] = copy_string(decl);
        table_add(*seen, copy_string(key), true);
        continue;
      }
      table_add(*selected_type_decl_index, copy_string(type_name), selected_decls.count);
    }

    array_add(*selected_decls, copy_string(decl));
    table_add(*seen, copy_string(key), true);
  }

  for decls_f {
    decl := it;
    key := ir_metal_compact_decl_key(decl);
    if key.count == 0 continue;
    found, _ := table_find(*seen, key);
    if found continue;

    is_forward := ir_metal_is_forward_type_decl(decl);
    type_name, type_name_ok := ir_metal_declared_type_name(decl);
    if type_name_ok && !is_forward {
      type_found, existing_index := table_find(*selected_type_decl_index, type_name);
      if type_found {
        // Prefer the later stage declaration for colliding type names.
        // This resolves stage-split spirv-cross output that may emit differing
        // definitions (for example, vector3 UBO packing variants) under the same type name.
        selected_decls[existing_index] = copy_string(decl);
        table_add(*seen, copy_string(key), true);
        continue;
      }
      table_add(*selected_type_decl_index, copy_string(type_name), selected_decls.count);
    }

    array_add(*selected_decls, copy_string(decl));
    table_add(*seen, copy_string(key), true);
  }

  for selected_decls a(*sb, it);
  return builder_to_string(*sb);
} @jdll_export 

spv_memory_model_from_text :: (spvasm: string) -> string {
  marker := "OpMemoryModel ";
  idx := find_index_from_left(spvasm, marker);
  if idx == -1 return "";
  start := idx + marker.count;
  if start >= spvasm.count return "";

  end := start;
  while end < spvasm.count && spvasm[end] != #char "\n" && spvasm[end] != #char "\r" end += 1;
  line: string;
  line.data = spvasm.data + start;
  line.count = end - start;
  return trim(line);
} @jdll_export

ir_find_struct_by_name_local :: (extra_structs: [] IR_Struct, name: string) -> *IR_Struct {
  for *extra_structs if it.name == name return it;
  return null;
}


ir_struct_has_pointer_fields_recursive_local :: (extra_structs: [] IR_Struct, name: string) -> bool {
  st := ir_find_struct_by_name_local(extra_structs, name);
  if !st return false;
  for st.fields {
    if it.type.kind == .POINTER return true;
    nested_name := it.type.struct_name;
    if nested_name.count != 0 && ir_struct_has_pointer_fields_recursive_local(extra_structs, nested_name) return true;
  }
  return false;
} @jdll_export 

ir_uses_pointer_abi_local :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool {
  for args {
    if it.type.kind != .POINTER || !it.type.pointee_is_struct || it.type.pointee_struct_name.count == 0 continue;
    if ir_struct_has_pointer_fields_recursive_local(extra_structs, it.type.pointee_struct_name) return true;
  }
  return false;
} @jdll_export

#scope_file

ir_metal_compact_decl_key :: (decl: string) -> string {
  out: [..] u8;
  for decl {
    ch := it;
    if ch == #char " " || ch == #char "\t" || ch == #char "\r" || ch == #char "\n" continue;
    array_add(*out, ch);
  }
  return string.{data = out.data, count = out.count};
}

ir_metal_find_preamble_end :: (source: string) -> s64 {
  marker := "using namespace metal;";
  index := find_index_from_left(source, marker);
  if index == -1 return 0;

  end := index + marker.count;
  while end < source.count && (source[end] == #char "\n" || source[end] == #char "\r") end += 1;
  return end;
}

ir_metal_is_forward_type_decl :: (decl: string) -> bool {
  text := trim_ascii_whitespace(decl);
  if text.count == 0 return false;
  if find_index_from_left(text, "{") != -1 return false;
  if !ends_with(text, ";") return false;
  if begins_with(text, "struct ") return true;
  if begins_with(text, "class ") return true;
  if begins_with(text, "enum ") return true;
  return false;
}

ir_metal_declared_type_name :: (decl: string) -> (string, bool) {
  text := trim_ascii_whitespace(decl);
  if text.count == 0 return "", false;
  keywords := string.["struct ", "class ", "enum "];
  for keywords {
    keyword := it;
    idx: s64 = -1;
    if begins_with(text, keyword) {
      idx = 0;
    } else if begins_with(text, "template") {
      idx = find_index_from_left(text, keyword);
    }
    if idx == -1 continue;
    type_name, ok := ir_metal_extract_type_name_after(text, idx + keyword.count);
    if ok return type_name, true;
  }
  return "", false;
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

expression_to_source_string :: (node: *Code_Node) -> string {
  sb: String_Builder;
  PP.print_expression(*sb, node);
  return builder_to_string(*sb);
}

ir_metal_extract_type_name_after :: (text: string, after_index: s64) -> (string, bool) {
  i := after_index;
  while i < text.count {
    ch := text[i];
    if ch != #char " " && ch != #char "\t" && ch != #char "\r" && ch != #char "\n" break;
    i += 1;
  }
  if i >= text.count return "", false;
  if !ir_metal_is_ident_char(text[i]) return "", false;
  start := i;
  while i < text.count && ir_metal_is_ident_char(text[i]) i += 1;
  if i <= start return "", false;
  out: string;
  out.data = text.data + start;
  out.count = i - start;
  return out, true;
}

ir_metal_is_ident_char :: (ch: u8) -> bool {
  return (ch >= #char "a" && ch <= #char "z") ||
         (ch >= #char "A" && ch <= #char "Z") ||
         (ch >= #char "0" && ch <= #char "9") ||
         ch == #char "_";
}

PP :: #import "Program_Print";
