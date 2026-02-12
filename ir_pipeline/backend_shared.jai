#scope_module

add_indents :: (sb: *String_Builder, indent: s64) #expand {
  for i: 0..indent*4 append(sb, " ");
}

type_contains_array :: (type: *Type_Info) -> bool {
  if !type return false;
  if type.type != .ARRAY return false;
  return true;
}

strip_redundant_outer_parens :: (in: string) -> string {
  if in.count == 0 return in;

  start := cast(s64) 0;
  end := in.count - 1;
  while start <= end && (in[start] == #char " " || in[start] == #char "\t" || in[start] == #char "\n" || in[start] == #char "\r")
    start += 1;
  while end >= start && (in[end] == #char " " || in[end] == #char "\t" || in[end] == #char "\n" || in[end] == #char "\r")
    end -= 1;
  if end - start + 1 < 2 {
    trimmed: string;
    trimmed.data = in.data + start;
    trimmed.count = end - start + 1;
    return trimmed;
  }

  trimmed: string;
  trimmed.data = in.data + start;
  trimmed.count = end - start + 1;

  if trimmed[0] != #char "(" || trimmed[trimmed.count-1] != #char ")" return trimmed;

  depth := 0;
  for i: 0..trimmed.count-1 {
    ch := trimmed[i];
    if ch == #char "(" depth += 1;
    if ch == #char ")" {
      depth -= 1;
      if depth == 0 && i != trimmed.count-1 return trimmed;
      if depth < 0 return trimmed;
    }
  }
  if depth != 0 return trimmed;

  stripped: string;
  stripped.data = trimmed.data + 1;
  stripped.count = trimmed.count - 2;
  return stripped;
}

report_array_parameter_not_supported :: (backend_name: string, decl: $T) #expand {
  if decl.type_inst && type_contains_array(decl.type_inst.result)
    compiler_report(tprint("% Backend: Functions with array parameters are not supported in Jai Shaders", backend_name), make_location(decl));
}

report_array_return_not_supported :: (backend_name: string, decl: $T) #expand {
  if decl.type_inst && type_contains_array(decl.type_inst.result)
    compiler_report(tprint("% Backend: Functions with array return types are not supported in Jai Shaders", backend_name), make_location(decl));
}

check_array_signature_support :: (backend_name: string, header: *Code_Procedure_Header) {
  for header.arguments report_array_parameter_not_supported(backend_name, it);
  for header.returns report_array_return_not_supported(backend_name, it);
}

split_array_type_and_suffix :: (backend_name: string, type: *Type_Info) -> (*Type_Info, string) {
  curr := type;
  suffix_builder: String_Builder;
  while curr && curr.type == .ARRAY {
    array_type := cast(*Type_Info_Array) curr;
    if array_type.array_type != .FIXED
      compiler_report(tprint("% Backend: Only fixed-size arrays are currently supported in Jai Shaders", backend_name));

    append(*suffix_builder, tprint("[%]", array_type.array_count));
    curr = array_type.element_type;
  }

  return curr, builder_to_string(*suffix_builder);
}

Unnamed_Struct_Entry :: struct {
  ptr: *Type_Info_Struct;
  name: string;
}

unnamed_struct_counter: s64;
unnamed_struct_entries: [..] Unnamed_Struct_Entry;

get_struct_type_name :: (struct_type: *Type_Info_Struct) -> string {
  if struct_type.name.count != 0 return struct_type.name;

  for unnamed_struct_entries {
    if it.ptr == struct_type return it.name;
  }

  unnamed_struct_counter += 1;
  name := tprint("UnnamedStruct%", unnamed_struct_counter);
  array_add(*unnamed_struct_entries, .{ptr = struct_type, name = name});
  struct_type.name = name;
  return name;
}

reset_unnamed_struct_cache :: () {
  unnamed_struct_counter = 0;
  array_reset(*unnamed_struct_entries);
}


get_buffer_binding_from_decl :: (decl: *Code_Declaration) -> (s64, bool) {
  suffix, found := declaration_get_note_suffix(decl, "buffer(");
  if !found return 0, false;

  value: s64 = 0;
  any_digit := false;
  for i: 0..suffix.count-1 {
    ch := suffix[i];
    if ch == #char ")" break;
    if ch < #char "0" || ch > #char "9" return 0, false;
    any_digit = true;
    value = value * 10 + (ch - #char "0");
  }
  if !any_digit return 0, false;
  return value, true;
}

find_buffer_param :: (header: *Code_Procedure_Header) -> (*Code_Declaration, s64, bool) {
  for header.arguments {
    binding, found := get_buffer_binding_from_decl(it);
    if found return it, binding, true;
  }
  return null, 0, false;
}

find_implicit_bindless_param :: (header: *Code_Procedure_Header) -> (*Code_Declaration, s64, bool) {
  candidate: *Code_Declaration = null;
  for header.arguments {
    if declaration_is_parameter_using(header, it) continue;
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if arg_type.type == .POINTER {
      pointer := cast(*Type_Info_Pointer) arg_type;
      if !pointer.pointer_to || pointer.pointer_to.type != .STRUCT continue;
    } else if arg_type.type != .STRUCT {
      continue;
    }
    if candidate return null, 0, false;
    candidate = it;
  }
  if candidate return candidate, 0, true;
  return null, 0, false;
}

bindless_struct_type_from_decl :: (decl: *Code_Declaration) -> (*Type_Info_Struct, bool) {
  if !decl return null, false;
  type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
  if !type return null, false;
  if type.type == .STRUCT return cast(*Type_Info_Struct) type, true;
  if type.type == .POINTER {
    pointer := cast(*Type_Info_Pointer) type;
    if pointer.pointer_to && pointer.pointer_to.type == .STRUCT return cast(*Type_Info_Struct) pointer.pointer_to, true;
  }
  return null, false;
}

find_bindless_param :: (header: *Code_Procedure_Header) -> (*Code_Declaration, s64, bool) {
  decl, binding, found := find_buffer_param(header);
  if found return decl, binding, true;
  decl2, binding2, found2 := find_implicit_bindless_param(header);
  return decl2, binding2, found2;
}
