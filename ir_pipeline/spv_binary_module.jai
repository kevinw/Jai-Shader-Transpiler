#scope_module

F16 :: #import "Float16";

SPV_MAGIC_NUMBER :: 0x07230203;
SPV_VERSION_1_5 :: 0x00010500;
SPV_GENERATOR_MAGIC :: 0;

SPV_Section :: enum {
  CAPABILITIES;
  EXT_INST_IMPORTS;
  MEMORY_MODEL;
  ENTRY_POINTS;
  EXECUTION_MODES;
  DEBUG;
  ANNOTATIONS;
  TYPES_CONSTANTS_GLOBALS;
  FUNCTIONS;
}

SPV_Inst :: struct {
  opcode: u16;
  words: [..] u32;
}

SPV_Module :: struct {
  capabilities: [..] SPV_Inst;
  ext_inst_imports: [..] SPV_Inst;
  memory_model: [..] SPV_Inst;
  entry_points: [..] SPV_Inst;
  execution_modes: [..] SPV_Inst;
  debug: [..] SPV_Inst;
  annotations: [..] SPV_Inst;
  types_constants_globals: [..] SPV_Inst;
  functions: [..] SPV_Inst;
  bound: u32;
}

SPV_Text_Type_Kind :: enum {
  UNKNOWN;
  BOOL;
  INT;
  FLOAT;
}

SPV_Text_Type_Info :: struct {
  id: u32;
  kind: SPV_Text_Type_Kind;
  width: u32;
  is_signed: bool;
}

SPV_Text_Parse_Context :: struct {
  known_types: [..] SPV_Text_Type_Info;
  in_function: bool;
}

spv_module_append_inst :: (m: *SPV_Module, section: SPV_Section, inst: SPV_Inst) {
  assert(m != null);
  if section == {
  case .CAPABILITIES;          array_add(*m.capabilities, inst);
  case .EXT_INST_IMPORTS;      array_add(*m.ext_inst_imports, inst);
  case .MEMORY_MODEL;          array_add(*m.memory_model, inst);
  case .ENTRY_POINTS;          array_add(*m.entry_points, inst);
  case .EXECUTION_MODES;       array_add(*m.execution_modes, inst);
  case .DEBUG;                 array_add(*m.debug, inst);
  case .ANNOTATIONS;           array_add(*m.annotations, inst);
  case .TYPES_CONSTANTS_GLOBALS; array_add(*m.types_constants_globals, inst);
  case .FUNCTIONS;             array_add(*m.functions, inst);
  }
}

spv_inst :: (opcode: u16, words: [] u32) -> SPV_Inst {
  out: SPV_Inst;
  out.opcode = opcode;
  for words array_add(*out.words, it);
  return out;
}

spv_module_append_words :: (m: *SPV_Module, section: SPV_Section, opcode: u16, words: ..u32) {
  assert(m != null);
  inst: SPV_Inst;
  inst.opcode = opcode;
  for words array_add(*inst.words, it);
  spv_module_append_inst(m, section, inst);
}

spv_module_append_string_inst :: (m: *SPV_Module, section: SPV_Section, opcode: u16, prefix_words: []u32, text: string) {
  assert(m != null);
  inst: SPV_Inst;
  inst.opcode = opcode;
  for prefix_words array_add(*inst.words, it);
  spv_append_string_words(*inst.words, text);
  spv_module_append_inst(m, section, inst);
}

spv_module_append_name :: (m: *SPV_Module, target_id: u32, text: string) {
  spv_module_append_string_inst(m, .DEBUG, SPV_OP_NAME, .[target_id], text);
}

spv_module_append_member_name :: (m: *SPV_Module, type_id: u32, member_index: u32, text: string) {
  spv_module_append_string_inst(m, .DEBUG, SPV_OP_MEMBER_NAME, .[type_id, member_index], text);
}

spv_module_append_ext_inst_import :: (m: *SPV_Module, result_id: u32, text: string) {
  spv_module_append_string_inst(m, .EXT_INST_IMPORTS, SPV_OP_EXT_INST_IMPORT, .[result_id], text);
}

spv_module_append_extension :: (m: *SPV_Module, text: string) {
  spv_module_append_string_inst(m, .EXT_INST_IMPORTS, SPV_OP_EXTENSION, .[], text);
}

spv_module_append_source :: (m: *SPV_Module, source_language: u32, version: u32) {
  spv_module_append_words(m, .DEBUG, SPV_OP_SOURCE, source_language, version);
}

spv_module_append_string :: (m: *SPV_Module, result_id: u32, text: string) {
  spv_module_append_string_inst(m, .DEBUG, SPV_OP_STRING, .[result_id], text);
}

spv_module_insert_string_after_sources :: (m: *SPV_Module, result_id: u32, text: string) {
  assert(m != null);
  inst: SPV_Inst;
  inst.opcode = SPV_OP_STRING;
  array_add(*inst.words, result_id);
  spv_append_string_words(*inst.words, text);

  insert_index: s64 = 0;
  for debug_inst, debug_index: m.debug {
    if debug_inst.opcode == SPV_OP_SOURCE {
      insert_index = debug_index + 1;
      continue;
    }
    break;
  }

  array_insert_at(*m.debug, inst, insert_index);
}

spv_module_append_line :: (m: *SPV_Module, file_id: u32, line: u32, column: u32) {
  spv_module_append_words(m, .FUNCTIONS, SPV_OP_LINE, file_id, line, column);
}

spv_module_append_entry_point :: (m: *SPV_Module, execution_model: u32, entry_id: u32, name: string, interface_ids: []u32) {
  assert(m != null);
  inst: SPV_Inst;
  inst.opcode = SPV_OP_ENTRY_POINT;
  array_add(*inst.words, execution_model, entry_id);
  spv_append_string_words(*inst.words, name);
  for interface_ids array_add(*inst.words, it);
  spv_module_append_inst(m, .ENTRY_POINTS, inst);
}

spv_module_word_count :: (m: *SPV_Module) -> s64 {
  total: s64 = 5;
  append_inst_count :: (items: [] SPV_Inst, total: *s64) {
    for items total.* += 1 + it.words.count;
  }
  append_inst_count(m.capabilities, *total);
  append_inst_count(m.ext_inst_imports, *total);
  append_inst_count(m.memory_model, *total);
  append_inst_count(m.entry_points, *total);
  append_inst_count(m.execution_modes, *total);
  append_inst_count(m.debug, *total);
  append_inst_count(m.annotations, *total);
  append_inst_count(m.types_constants_globals, *total);
  append_inst_count(m.functions, *total);
  return total;
}

spv_serialize_module_binary :: (m: *SPV_Module) -> [] u8 {
  assert(m != null);
  word_count := spv_module_word_count(m);
  bytes: [] u8 = NewArray(word_count * 4, u8);
  out := cast(*u32) bytes.data;

  emit_word :: (out: **u32, value: u32) {
    out.*.* = value;
    out.* += 1;
  }

  emit_inst :: (out: **u32, items: [] SPV_Inst) {
    for items {
      word_count := cast(u32) (1 + it.words.count);
      emit_word(out, (word_count << 16) | cast(u32) it.opcode);
      for it.words emit_word(out, it);
    }
  }

  emit_word(*out, SPV_MAGIC_NUMBER);
  emit_word(*out, SPV_VERSION_1_5);
  emit_word(*out, SPV_GENERATOR_MAGIC);
  emit_word(*out, m.bound);
  emit_word(*out, 0);

  emit_inst(*out, m.capabilities);
  emit_inst(*out, m.ext_inst_imports);
  emit_inst(*out, m.memory_model);
  emit_inst(*out, m.entry_points);
  emit_inst(*out, m.execution_modes);
  emit_inst(*out, m.debug);
  emit_inst(*out, m.annotations);
  emit_inst(*out, m.types_constants_globals);
  emit_inst(*out, m.functions);

  return bytes;
}

spv_ingest_text_into_module :: (m: *SPV_Module, text: string) -> (ok: bool, diag: IR_Diagnostic) {
  assert(m != null);
  ctx: SPV_Text_Parse_Context;
  start: s64 = 0;
  while start < text.count {
    end := start;
    while end < text.count && text[end] != #char "\n" end += 1;
    line := string.{end - start, text.data + start};
    parsed_ok, parsed_diag := spv_ingest_text_line(m, *ctx, line);
    if !parsed_ok return false, parsed_diag;
    start = end + 1;
  }
  return true, {};
}

spv_ingest_text_line :: (m: *SPV_Module, ctx: *SPV_Text_Parse_Context, raw_line: string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  line := trim(raw_line);
  if line.count == 0 return true, {};
  if line[0] == #char ";" return true, {};

  tokens := spv_tokenize_text_line(line);
  if tokens.count == 0 return true, {};

  result_id: u32 = 0;
  opcode_token_index: s64 = 0;
  operand_start: s64 = 1;
  has_result_id := false;
  if tokens.count >= 3 && tokens[1] == "=" {
    result_id, has_result_id = spv_parse_id_token(tokens[0]);
    if !has_result_id return_err("SPIR-V binary backend: failed parsing result id in '%'.", line);
    opcode_token_index = 2;
    operand_start = 3;
  }

  opcode_name := tokens[opcode_token_index];
  opcode, opcode_ok := spv_lookup_opcode(opcode_name);
  if !opcode_ok return_err("SPIR-V binary backend: unsupported opcode '%'.", opcode_name);

  words: [..] u32;
  operands := spv_slice_tokens(tokens, operand_start);

  append_result_type_and_id :: (words: *[..] u32, operands: [] string, result_id: u32) -> (remaining: [] string, ok: bool) {
    if operands.count == 0 return operands, false;
    result_type, result_type_ok := spv_parse_id_token(operands[0]);
    if !result_type_ok return operands, false;
    array_add(words, result_type);
    array_add(words, result_id);
    remaining := operands;
    remaining.data += 1;
    remaining.count -= 1;
    return remaining, true;
  }

  if opcode == SPV_OP_CAPABILITY {
    if operands.count != 1 return_err("OpCapability expects 1 operand.");
    value, value_ok := spv_lookup_capability(operands[0]);
    if !value_ok return_err("Unknown capability '%'.", operands[0]);
    array_add(*words, value);
  } else if opcode == SPV_OP_EXT_INST_IMPORT {
    if !has_result_id || operands.count != 1 return_err("OpExtInstImport expects result id and 1 operand.");
    array_add(*words, result_id);
    spv_append_string_words(*words, operands[0]);
  } else if opcode == SPV_OP_MEMORY_MODEL {
    if operands.count != 2 return_err("OpMemoryModel expects 2 operands.");
    addressing, addressing_ok := spv_lookup_addressing_model(operands[0]);
    memory_model, memory_model_ok := spv_lookup_memory_model(operands[1]);
    if !addressing_ok || !memory_model_ok return_err("Invalid OpMemoryModel line '%'.", line);
    array_add(*words, addressing, memory_model);
  } else if opcode == SPV_OP_ENTRY_POINT {
    if operands.count < 3 return_err("OpEntryPoint expects at least 3 operands.");
    execution_model, model_ok := spv_lookup_execution_model(operands[0]);
    entry_id, entry_ok := spv_parse_id_token(operands[1]);
    if !model_ok || !entry_ok return_err("Invalid OpEntryPoint line '%'.", line);
    array_add(*words, execution_model, entry_id);
    spv_append_string_words(*words, operands[2]);
    for it_index: 3..operands.count-1 {
      id, id_ok := spv_parse_id_token(operands[it_index]);
      if !id_ok return_err("Invalid OpEntryPoint interface id in '%'.", line);
      array_add(*words, id);
    }
  } else if opcode == SPV_OP_EXECUTION_MODE {
    if operands.count < 2 return_err("OpExecutionMode expects at least 2 operands.");
    target_id, target_ok := spv_parse_id_token(operands[0]);
    mode, mode_ok := spv_lookup_execution_mode(operands[1]);
    if !target_ok || !mode_ok return_err("Invalid OpExecutionMode line '%'.", line);
    array_add(*words, target_id, mode);
    for it_index: 2..operands.count-1 {
      lit, lit_ok := spv_parse_u32_token(operands[it_index]);
      if !lit_ok return_err("Invalid OpExecutionMode literal in '%'.", line);
      array_add(*words, lit);
    }
  } else if opcode == SPV_OP_SOURCE {
    if operands.count < 2 return_err("OpSource expects at least 2 operands.");
    source_lang, source_ok := spv_lookup_source_language(operands[0]);
    version, version_ok := spv_parse_u32_token(operands[1]);
    if !source_ok || !version_ok return_err("Invalid OpSource line '%'.", line);
    array_add(*words, source_lang, version);
  } else if opcode == SPV_OP_STRING {
    if !has_result_id || operands.count != 1 return_err("OpString expects result id and 1 operand.");
    array_add(*words, result_id);
    spv_append_string_words(*words, operands[0]);
  } else if opcode == SPV_OP_LINE {
    if operands.count != 3 return_err("OpLine expects 3 operands.");
    file_id, file_ok := spv_parse_id_token(operands[0]);
    line_value, line_ok := spv_parse_u32_token(operands[1]);
    column_value, column_ok := spv_parse_u32_token(operands[2]);
    if !file_ok || !line_ok || !column_ok return_err("Invalid OpLine line '%'.", line);
    array_add(*words, file_id, line_value, column_value);
  } else if opcode == SPV_OP_NAME {
    if operands.count != 2 return_err("OpName expects 2 operands.");
    target_id, target_ok := spv_parse_id_token(operands[0]);
    if !target_ok return_err("Invalid OpName target id in '%'.", line);
    array_add(*words, target_id);
    spv_append_string_words(*words, operands[1]);
  } else if opcode == SPV_OP_MEMBER_NAME {
    if operands.count != 3 return_err("OpMemberName expects 3 operands.");
    type_id, type_ok := spv_parse_id_token(operands[0]);
    member_index, member_ok := spv_parse_u32_token(operands[1]);
    if !type_ok || !member_ok return_err("Invalid OpMemberName line '%'.", line);
    array_add(*words, type_id, member_index);
    spv_append_string_words(*words, operands[2]);
  } else if opcode == SPV_OP_DECORATE {
    if operands.count < 2 return_err("OpDecorate expects at least 2 operands.");
    target_id, target_ok := spv_parse_id_token(operands[0]);
    decoration, decoration_ok := spv_lookup_decoration(operands[1]);
    if !target_ok || !decoration_ok return_err("Invalid OpDecorate line '%'.", line);
    array_add(*words, target_id, decoration);
    extra_ok, extra_diag := spv_parse_decoration_operands(*words, decoration, spv_slice_tokens(operands, 2));
    if !extra_ok return false, extra_diag;
  } else if opcode == SPV_OP_MEMBER_DECORATE {
    if operands.count < 3 return_err("OpMemberDecorate expects at least 3 operands.");
    type_id, type_ok := spv_parse_id_token(operands[0]);
    member_index, member_ok := spv_parse_u32_token(operands[1]);
    decoration, decoration_ok := spv_lookup_decoration(operands[2]);
    if !type_ok || !member_ok || !decoration_ok return_err("Invalid OpMemberDecorate line '%'.", line);
    array_add(*words, type_id, member_index, decoration);
    extra_ok, extra_diag := spv_parse_decoration_operands(*words, decoration, spv_slice_tokens(operands, 3));
    if !extra_ok return false, extra_diag;
  } else if opcode == SPV_OP_TYPE_VOID || opcode == SPV_OP_TYPE_BOOL || opcode == SPV_OP_TYPE_SAMPLER {
    if !has_result_id return_err("% requires a result id.", opcode_name);
    array_add(*words, result_id);
  } else if opcode == SPV_OP_TYPE_FUNCTION || opcode == SPV_OP_TYPE_RUNTIME_ARRAY || opcode == SPV_OP_TYPE_SAMPLED_IMAGE ||
            opcode == SPV_OP_TYPE_ARRAY {
    if !has_result_id return_err("% requires a result id.", opcode_name);
    array_add(*words, result_id);
    for operands {
      value, value_ok := spv_parse_id_token(it);
      if !value_ok return_err("Invalid id operand in '%'.", line);
      array_add(*words, value);
    }
  } else if opcode == SPV_OP_TYPE_MATRIX {
    if !has_result_id || operands.count != 2 return_err("OpTypeMatrix expects result id, vector type id, and column count.");
    column_type, column_type_ok := spv_parse_id_token(operands[0]);
    column_count, column_count_ok := spv_parse_u32_token(operands[1]);
    if !column_type_ok || !column_count_ok return_err("Invalid OpTypeMatrix line '%'.", line);
    array_add(*words, result_id, column_type, column_count);
  } else if opcode == SPV_OP_TYPE_INT {
    if !has_result_id || operands.count != 2 return_err("OpTypeInt expects result id and 2 operands.");
    width, width_ok := spv_parse_u32_token(operands[0]);
    signedness, signedness_ok := spv_parse_u32_token(operands[1]);
    if !width_ok || !signedness_ok return_err("Invalid OpTypeInt line '%'.", line);
    array_add(*words, result_id, width, signedness);
    spv_register_type(ctx, .{id = result_id, kind = .INT, width = width, is_signed = signedness != 0});
  } else if opcode == SPV_OP_TYPE_FLOAT {
    if !has_result_id || operands.count != 1 return_err("OpTypeFloat expects result id and 1 operand.");
    width, width_ok := spv_parse_u32_token(operands[0]);
    if !width_ok return_err("Invalid OpTypeFloat line '%'.", line);
    array_add(*words, result_id, width);
    spv_register_type(ctx, .{id = result_id, kind = .FLOAT, width = width});
  } else if opcode == SPV_OP_TYPE_VECTOR || opcode == SPV_OP_TYPE_POINTER || opcode == SPV_OP_TYPE_FORWARD_POINTER {
    if !has_result_id || operands.count < 2 return_err("% expects a result id and operands.", opcode_name);
    array_add(*words, result_id);
    if opcode == SPV_OP_TYPE_POINTER || opcode == SPV_OP_TYPE_FORWARD_POINTER {
      storage_class, storage_ok := spv_lookup_storage_class(operands[0]);
      if !storage_ok return_err("Invalid storage class in '%'.", line);
      array_add(*words, storage_class);
      for it_index: 1..operands.count-1 {
        value, value_ok := spv_parse_id_token(operands[it_index]);
        if !value_ok return_err("Invalid id operand in '%'.", line);
        array_add(*words, value);
      }
    } else {
      comp_type, comp_ok := spv_parse_id_token(operands[0]);
      count, count_ok := spv_parse_u32_token(operands[1]);
      if !comp_ok || !count_ok return_err("Invalid OpTypeVector line '%'.", line);
      array_add(*words, comp_type, count);
    }
  } else if opcode == SPV_OP_TYPE_STRUCT {
    if !has_result_id return_err("OpTypeStruct requires a result id.");
    array_add(*words, result_id);
    for operands {
      value, value_ok := spv_parse_id_token(it);
      if !value_ok return_err("Invalid OpTypeStruct member type in '%'.", line);
      array_add(*words, value);
    }
  } else if opcode == SPV_OP_TYPE_IMAGE {
    if !has_result_id || operands.count != 7 return_err("OpTypeImage expects 7 operands after the result id.");
    sampled_type, sampled_type_ok := spv_parse_id_token(operands[0]);
    dim, dim_ok := spv_lookup_dim(operands[1]);
    depth, depth_ok := spv_parse_u32_token(operands[2]);
    arrayed, arrayed_ok := spv_parse_u32_token(operands[3]);
    ms, ms_ok := spv_parse_u32_token(operands[4]);
    sampled, sampled_ok := spv_parse_u32_token(operands[5]);
    image_format, image_format_ok := spv_lookup_image_format(operands[6]);
    if !sampled_type_ok || !dim_ok || !depth_ok || !arrayed_ok || !ms_ok || !sampled_ok || !image_format_ok return_err("Invalid OpTypeImage line '%'.", line);
    array_add(*words, result_id, sampled_type, dim, depth, arrayed, ms, sampled, image_format);
  } else if opcode == SPV_OP_CONSTANT_TRUE || opcode == SPV_OP_CONSTANT_FALSE ||
            opcode == SPV_OP_SPEC_CONSTANT_TRUE || opcode == SPV_OP_SPEC_CONSTANT_FALSE {
    if !has_result_id || operands.count != 1 return_err("% expects result type.", opcode_name);
    result_type, result_type_ok := spv_parse_id_token(operands[0]);
    if !result_type_ok return_err("Invalid boolean constant line '%'.", line);
    array_add(*words, result_type, result_id);
  } else if opcode == SPV_OP_CONSTANT || opcode == SPV_OP_SPEC_CONSTANT {
    remaining, remaining_ok := append_result_type_and_id(*words, operands, result_id);
    if !remaining_ok || remaining.count != 1 return_err("% expects one literal operand.", opcode_name);
    result_type_id := words[0];
    extra_ok, extra_diag := spv_parse_constant_literal(*words, ctx, result_type_id, remaining[0]);
    if !extra_ok return false, extra_diag;
  } else if opcode == SPV_OP_CONSTANT_NULL {
    if !has_result_id || operands.count != 1 return_err("OpConstantNull expects result type.");
    result_type, result_type_ok := spv_parse_id_token(operands[0]);
    if !result_type_ok return_err("Invalid OpConstantNull line '%'.", line);
    array_add(*words, result_type, result_id);
  } else if opcode == SPV_OP_SPEC_CONSTANT_COMPOSITE {
    remaining, remaining_ok := append_result_type_and_id(*words, operands, result_id);
    if !remaining_ok return_err("OpSpecConstantComposite expects result type.");
    for remaining {
      value, value_ok := spv_parse_id_token(it);
      if !value_ok return_err("Invalid composite id in '%'.", line);
      array_add(*words, value);
    }
  } else if opcode == SPV_OP_VARIABLE {
    if !has_result_id || operands.count < 2 return_err("OpVariable expects result type and storage class.");
    result_type, result_type_ok := spv_parse_id_token(operands[0]);
    storage_class, storage_ok := spv_lookup_storage_class(operands[1]);
    if !result_type_ok || !storage_ok return_err("Invalid OpVariable line '%'.", line);
    array_add(*words, result_type, result_id, storage_class);
    if operands.count >= 3 {
      initializer, initializer_ok := spv_parse_id_token(operands[2]);
      if !initializer_ok return_err("Invalid OpVariable initializer id in '%'.", line);
      array_add(*words, initializer);
    }
  } else if opcode == SPV_OP_FUNCTION {
    if !has_result_id || operands.count != 3 return_err("OpFunction expects result type, function control, and type.");
    result_type, result_type_ok := spv_parse_id_token(operands[0]);
    function_control, function_control_ok := spv_lookup_function_control(operands[1]);
    fn_type, fn_type_ok := spv_parse_id_token(operands[2]);
    if !result_type_ok || !function_control_ok || !fn_type_ok return_err("Invalid OpFunction line '%'.", line);
    array_add(*words, result_type, result_id, function_control, fn_type);
  } else if opcode == SPV_OP_LABEL {
    if !has_result_id return_err("OpLabel requires a result id.");
    array_add(*words, result_id);
  } else if opcode == SPV_OP_SELECTION_MERGE {
    if operands.count != 2 return_err("OpSelectionMerge expects merge block and control mask.");
    merge_id, merge_ok := spv_parse_id_token(operands[0]);
    control, control_ok := spv_lookup_selection_control(operands[1]);
    if !merge_ok || !control_ok return_err("Invalid OpSelectionMerge line '%'.", line);
    array_add(*words, merge_id, control);
  } else if opcode == SPV_OP_LOOP_MERGE {
    if operands.count != 3 return_err("OpLoopMerge expects merge block, continue block, and control mask.");
    merge_id, merge_ok := spv_parse_id_token(operands[0]);
    continue_id, continue_ok := spv_parse_id_token(operands[1]);
    control, control_ok := spv_lookup_loop_control(operands[2]);
    if !merge_ok || !continue_ok || !control_ok return_err("Invalid OpLoopMerge line '%'.", line);
    array_add(*words, merge_id, continue_id, control);
  } else if opcode == SPV_OP_SWITCH {
    if operands.count < 2 return_err("OpSwitch expects selector and default label.");
    selector_id, selector_ok := spv_parse_id_token(operands[0]);
    default_id, default_ok := spv_parse_id_token(operands[1]);
    if !selector_ok || !default_ok return_err("Invalid OpSwitch line '%'.", line);
    array_add(*words, selector_id, default_id);
    if ((operands.count - 2) % 2) != 0 return_err("OpSwitch case operands must come in pairs.");
    i: s64 = 2;
    while i < operands.count {
      literal, literal_ok := spv_parse_u32_token(operands[i]);
      label_id, label_ok := spv_parse_id_token(operands[i+1]);
      if !literal_ok || !label_ok return_err("Invalid OpSwitch case in '%'.", line);
      array_add(*words, literal, label_id);
      i += 2;
    }
  } else {
    generic_ok, generic_diag := spv_parse_generic_instruction(*words, ctx, opcode, has_result_id, result_id, operands, line);
    if !generic_ok return false, generic_diag;
  }

  section := spv_classify_instruction_section(ctx, opcode);
  spv_module_append_inst(m, section, .{opcode = opcode, words = words});
  if opcode == SPV_OP_FUNCTION ctx.in_function = true;
  if opcode == SPV_OP_FUNCTION_END ctx.in_function = false;
  return true, {};
}

spv_parse_generic_instruction :: (words: *[..] u32, ctx: *SPV_Text_Parse_Context, opcode: u16, has_result_id: bool, result_id: u32, operands: [] string, line: string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }
  _ = ctx;
  remaining_operands := operands;

  if spv_opcode_requires_result_type_and_id(opcode) {
    if !has_result_id || remaining_operands.count == 0 return_err("Instruction '%' expects result type and result id.", line);
    result_type, result_type_ok := spv_parse_id_token(remaining_operands[0]);
    if !result_type_ok return_err("Instruction '%' has invalid result type id.", line);
    array_add(words, result_type, result_id);
    remaining_operands = spv_slice_tokens(remaining_operands, 1);
  } else if spv_opcode_requires_result_id_only(opcode) {
    if !has_result_id return_err("Instruction '%' expects result id.", line);
    array_add(words, result_id);
  }

  if opcode == SPV_OP_EXT_INST {
    if remaining_operands.count < 2 return_err("OpExtInst expects set id and extinst opcode.");
    set_id, set_id_ok := spv_parse_id_token(remaining_operands[0]);
    extinst, extinst_ok := spv_lookup_glsl_extinst(remaining_operands[1]);
    if !set_id_ok return_err("Invalid OpExtInst set id '%' in line '%'.", remaining_operands[0], line);
    if !extinst_ok return_err("Invalid OpExtInst opcode '%' in line '%'.", remaining_operands[1], line);
    array_add(words, set_id, extinst);
    for it_index: 2..remaining_operands.count-1 {
      value, value_ok := spv_parse_id_token(remaining_operands[it_index]);
      if !value_ok return_err("Invalid OpExtInst operand in '%'.", line);
      array_add(words, value);
    }
    return true, {};
  }

  if opcode == SPV_OP_LOAD {
    if remaining_operands.count < 1 return_err("OpLoad expects pointer operand.");
    ptr_id, ptr_ok := spv_parse_id_token(remaining_operands[0]);
    if !ptr_ok return_err("Invalid OpLoad line '%'.", line);
    array_add(words, ptr_id);
    if remaining_operands.count >= 3 {
      if remaining_operands[1] != "Aligned" return_err("Unsupported OpLoad memory access in '%'.", line);
      align, align_ok := spv_parse_u32_token(remaining_operands[2]);
      if !align_ok return_err("Invalid OpLoad alignment in '%'.", line);
      array_add(words, SPV_MEMORY_ACCESS_ALIGNED_MASK, align);
    }
    return true, {};
  }

  if opcode == SPV_OP_STORE {
    if remaining_operands.count < 2 return_err("OpStore expects pointer and object operands.");
    ptr_id, ptr_ok := spv_parse_id_token(remaining_operands[0]);
    object_id, object_ok := spv_parse_id_token(remaining_operands[1]);
    if !ptr_ok || !object_ok return_err("Invalid OpStore line '%'.", line);
    array_add(words, ptr_id, object_id);
    if remaining_operands.count >= 4 {
      if remaining_operands[2] != "Aligned" return_err("Unsupported OpStore memory access in '%'.", line);
      align, align_ok := spv_parse_u32_token(remaining_operands[3]);
      if !align_ok return_err("Invalid OpStore alignment in '%'.", line);
      array_add(words, SPV_MEMORY_ACCESS_ALIGNED_MASK, align);
    }
    return true, {};
  }

  if opcode == SPV_OP_BRANCH || opcode == SPV_OP_RETURN || opcode == SPV_OP_KILL || opcode == SPV_OP_UNREACHABLE {
    for remaining_operands {
      value, value_ok := spv_parse_id_token_or_u32(it);
      if !value_ok return_err("Invalid operand in '%'.", line);
      array_add(words, value);
    }
    return true, {};
  }

  for remaining_operands {
    value, value_ok := spv_parse_id_token_or_u32(it);
    if !value_ok return_err("Unsupported operand '%' in '%'.", it, line);
    array_add(words, value);
  }
  return true, {};
}

spv_classify_instruction_section :: (ctx: *SPV_Text_Parse_Context, opcode: u16) -> SPV_Section {
  if ctx && ctx.in_function return .FUNCTIONS;
  if opcode == SPV_OP_CAPABILITY      return .CAPABILITIES;
  if opcode == SPV_OP_EXT_INST_IMPORT return .EXT_INST_IMPORTS;
  if opcode == SPV_OP_MEMORY_MODEL    return .MEMORY_MODEL;
  if opcode == SPV_OP_ENTRY_POINT     return .ENTRY_POINTS;
  if opcode == SPV_OP_EXECUTION_MODE  return .EXECUTION_MODES;
  if opcode == SPV_OP_SOURCE || opcode == SPV_OP_NAME || opcode == SPV_OP_MEMBER_NAME || opcode == SPV_OP_STRING return .DEBUG;
  if opcode == SPV_OP_LINE return .FUNCTIONS;
  if opcode == SPV_OP_DECORATE || opcode == SPV_OP_MEMBER_DECORATE return .ANNOTATIONS;
  if opcode == SPV_OP_FUNCTION || opcode == SPV_OP_LABEL || opcode == SPV_OP_FUNCTION_END ||
     opcode == SPV_OP_BRANCH || opcode == SPV_OP_BRANCH_CONDITIONAL || opcode == SPV_OP_SWITCH ||
     opcode == SPV_OP_RETURN || opcode == SPV_OP_KILL || opcode == SPV_OP_UNREACHABLE ||
     opcode == SPV_OP_SELECTION_MERGE || opcode == SPV_OP_LOOP_MERGE {
    return .FUNCTIONS;
  }
  return .TYPES_CONSTANTS_GLOBALS;
}

spv_opcode_requires_result_type_and_id :: (opcode: u16) -> bool {
  if opcode == SPV_OP_EXT_INST return true;
  if opcode == SPV_OP_COMPOSITE_CONSTRUCT return true;
  if opcode == SPV_OP_COMPOSITE_EXTRACT return true;
  if opcode == SPV_OP_VECTOR_SHUFFLE return true;
  if opcode == SPV_OP_ACCESS_CHAIN return true;
  if opcode == SPV_OP_LOAD return true;
  if opcode == SPV_OP_SAMPLE_IMAGE return true;
  if opcode == SPV_OP_IMAGE_SAMPLE_IMPLICIT_LOD return true;
  if opcode == SPV_OP_SELECT return true;
  if opcode == SPV_OP_MATRIX_TIMES_VECTOR return true;
  if opcode == SPV_OP_FADD return true;
  if opcode == SPV_OP_FSUB return true;
  if opcode == SPV_OP_FMUL return true;
  if opcode == SPV_OP_FDIV return true;
  if opcode == SPV_OP_FREM return true;
  if opcode == SPV_OP_FNEGATE return true;
  if opcode == SPV_OP_SNEGATE return true;
  if opcode == SPV_OP_IADD return true;
  if opcode == SPV_OP_ISUB return true;
  if opcode == SPV_OP_IMUL return true;
  if opcode == SPV_OP_SDIV return true;
  if opcode == SPV_OP_UDIV return true;
  if opcode == SPV_OP_SMOD return true;
  if opcode == SPV_OP_UMOD return true;
  if opcode == SPV_OP_SHIFT_LEFT_LOGICAL return true;
  if opcode == SPV_OP_SHIFT_RIGHT_LOGICAL return true;
  if opcode == SPV_OP_SHIFT_RIGHT_ARITHMETIC return true;
  if opcode == SPV_OP_BITWISE_OR return true;
  if opcode == SPV_OP_BITWISE_AND return true;
  if opcode == SPV_OP_BITWISE_XOR return true;
  if opcode == SPV_OP_NOT return true;
  if opcode == SPV_OP_LOGICAL_NOT return true;
  if opcode == SPV_OP_BITCAST return true;
  if opcode == SPV_OP_FCONVERT return true;
  if opcode == SPV_OP_SCONVERT return true;
  if opcode == SPV_OP_UCONVERT return true;
  if opcode == SPV_OP_CONVERT_F_TO_S return true;
  if opcode == SPV_OP_CONVERT_F_TO_U return true;
  if opcode == SPV_OP_CONVERT_S_TO_F return true;
  if opcode == SPV_OP_CONVERT_U_TO_F return true;
  if opcode == SPV_OP_IEQUAL return true;
  if opcode == SPV_OP_INOT_EQUAL return true;
  if opcode == SPV_OP_FORD_EQUAL return true;
  if opcode == SPV_OP_FORD_NOT_EQUAL return true;
  if opcode == SPV_OP_FORD_LESS_THAN return true;
  if opcode == SPV_OP_FORD_LESS_THAN_EQUAL return true;
  if opcode == SPV_OP_FORD_GREATER_THAN return true;
  if opcode == SPV_OP_FORD_GREATER_THAN_EQUAL return true;
  if opcode == SPV_OP_SLESS_THAN return true;
  if opcode == SPV_OP_SLESS_THAN_EQUAL return true;
  if opcode == SPV_OP_SGREATER_THAN return true;
  if opcode == SPV_OP_SGREATER_THAN_EQUAL return true;
  if opcode == SPV_OP_ULESS_THAN return true;
  if opcode == SPV_OP_ULESS_THAN_EQUAL return true;
  if opcode == SPV_OP_UGREATER_THAN return true;
  if opcode == SPV_OP_UGREATER_THAN_EQUAL return true;
  if opcode == SPV_OP_ATOMIC_IADD return true;
  if opcode == SPV_OP_ATOMIC_EXCHANGE return true;
  if opcode == SPV_OP_ATOMIC_COMPARE_EXCHANGE return true;
  return false;
}

spv_opcode_requires_result_id_only :: (opcode: u16) -> bool {
  if opcode == SPV_OP_LABEL return true;
  return false;
}

spv_append_string_words :: (dst: *[..] u32, text: string) {
  assert(dst != null);
  index: s64 = 0;
  while index <= text.count {
    bytes: [4] u8;
    for byte_index: 0..3 {
      absolute := index + byte_index;
      if absolute < text.count bytes[byte_index] = text[absolute];
    }
    word := (.*) cast(*u32)*bytes;
    array_add(dst, word);
    index += 4;
    if index > text.count break;
  }
}

spv_tokenize_text_line :: (line: string) -> [..] string {
  tokens: [..] string;
  i: s64 = 0;
  while i < line.count {
    ch := line[i];
    if ch == #char " " || ch == #char "\t" {
      i += 1;
      continue;
    }

    if ch == #char "\"" {
      start := i + 1;
      i += 1;
      while i < line.count && line[i] != #char "\"" i += 1;
      if i > start {
        token := string.{i - start, line.data + start};
        array_add(*tokens, token);
      } else {
        array_add(*tokens, "");
      }
      if i < line.count i += 1;
      continue;
    }

    start := i;
    while i < line.count && line[i] != #char " " && line[i] != #char "\t" i += 1;
    token := string.{i - start, line.data + start};
    array_add(*tokens, token);
  }

  return tokens;
}

spv_register_type :: (ctx: *SPV_Text_Parse_Context, info: SPV_Text_Type_Info) {
  assert(ctx != null);
  for *ctx.known_types {
    if it.id != info.id continue;
    it.kind = info.kind;
    it.width = info.width;
    it.is_signed = info.is_signed;
    return;
  }
  array_add(*ctx.known_types, info);
}

spv_find_type :: (ctx: *SPV_Text_Parse_Context, id: u32) -> *SPV_Text_Type_Info {
  assert(ctx != null);
  for *ctx.known_types if it.id == id return it;
  return null;
}

spv_parse_constant_literal :: (words: *[..] u32, ctx: *SPV_Text_Parse_Context, result_type_id: u32, token: string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }
  info := spv_find_type(ctx, result_type_id);
  if !info return_err("Unknown result type id % for constant literal '%'.", result_type_id, token);

  if info.kind == .INT {
    value, value_ok := string_to_int(token);
    if !value_ok return_err("Failed parsing integer literal '%'.", token);
    if info.width == 64 {
      bits := cast(u64) value;
      if info.is_signed bits = cast(u64) cast(s64) value;
      array_add(words, cast(u32) bits, cast(u32) (bits >> 32));
      return true, {};
    }
    array_add(words, cast(u32) value);
    return true, {};
  }

  if info.kind == .FLOAT {
    if info.width == 16 {
      value, value_ok, remainder := string_to_float(token);
      if !value_ok || remainder.count != 0 return_err("Failed parsing float16 literal '%'.", token);
      half := F16.float32_to_float16(value);
      array_add(words, cast(u32) cast(u16) half);
      return true, {};
    }
    if info.width == 32 {
      value, value_ok, remainder := string_to_float(token);
      if !value_ok || remainder.count != 0 return_err("Failed parsing float literal '%'.", token);
      bits := (.*) cast(*u32)*value;
      array_add(words, bits);
      return true, {};
    }
  }

  return_err("Unsupported constant literal '%' for type id %.", token, result_type_id);
}

spv_parse_decoration_operands :: (words: *[..] u32, decoration: u32, operands: [] string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }
  if decoration == SPV_DECORATION_BUILTIN {
    if operands.count != 1 return_err("BuiltIn decoration expects 1 operand.");
    builtin, builtin_ok := spv_lookup_builtin(operands[0]);
    if !builtin_ok return_err("Unknown BuiltIn '%'.", operands[0]);
    array_add(words, builtin);
    return true, {};
  }

  for operands {
    value, value_ok := spv_parse_id_token_or_u32(it);
    if !value_ok return_err("Unsupported decoration operand '%'.", it);
    array_add(words, value);
  }
  return true, {};
}

spv_parse_id_token_or_u32 :: (token: string) -> (u32, bool) {
  id, id_ok := spv_parse_id_token(token);
  if id_ok return id, true;
  value, value_ok := spv_parse_u32_token(token);
  return value, value_ok;
}

spv_slice_tokens :: (tokens: [] string, start: s64) -> [] string {
  if start < 0 start = 0;
  if start > tokens.count start = tokens.count;
  return .{count = tokens.count - start, data = tokens.data + start};
}

spv_parse_id_token :: (token: string) -> (u32, bool) {
  if token.count < 2 return 0, false;
  if token[0] != #char "%" return 0, false;
  v, ok := string_to_int(string.{token.count - 1, token.data + 1});
  if !ok || v < 0 return 0, false;
  return cast(u32) v, true;
}

spv_parse_u32_token :: (token: string) -> (u32, bool) {
  v, ok := string_to_int(token);
  if !ok || v < 0 || v > 0xFFFF_FFFF return 0, false;
  return cast(u32) v, true;
}

spv_lookup_opcode :: (name: string) -> (u16, bool) {
  if name == {
  case "OpSource";                 return SPV_OP_SOURCE, true;
  case "OpName";                   return SPV_OP_NAME, true;
  case "OpMemberName";             return SPV_OP_MEMBER_NAME, true;
  case "OpString";                 return SPV_OP_STRING, true;
  case "OpLine";                   return SPV_OP_LINE, true;
  case "OpExtInstImport";          return SPV_OP_EXT_INST_IMPORT, true;
  case "OpExtInst";                return SPV_OP_EXT_INST, true;
  case "OpMemoryModel";            return SPV_OP_MEMORY_MODEL, true;
  case "OpEntryPoint";             return SPV_OP_ENTRY_POINT, true;
  case "OpExecutionMode";          return SPV_OP_EXECUTION_MODE, true;
  case "OpCapability";             return SPV_OP_CAPABILITY, true;
  case "OpTypeVoid";               return SPV_OP_TYPE_VOID, true;
  case "OpTypeBool";               return SPV_OP_TYPE_BOOL, true;
  case "OpTypeInt";                return SPV_OP_TYPE_INT, true;
  case "OpTypeFloat";              return SPV_OP_TYPE_FLOAT, true;
  case "OpTypeVector";             return SPV_OP_TYPE_VECTOR, true;
  case "OpTypeMatrix";             return SPV_OP_TYPE_MATRIX, true;
  case "OpTypeImage";              return SPV_OP_TYPE_IMAGE, true;
  case "OpTypeSampler";            return SPV_OP_TYPE_SAMPLER, true;
  case "OpTypeSampledImage";       return SPV_OP_TYPE_SAMPLED_IMAGE, true;
  case "OpTypeArray";              return SPV_OP_TYPE_ARRAY, true;
  case "OpTypeRuntimeArray";       return SPV_OP_TYPE_RUNTIME_ARRAY, true;
  case "OpTypeStruct";             return SPV_OP_TYPE_STRUCT, true;
  case "OpTypePointer";            return SPV_OP_TYPE_POINTER, true;
  case "OpTypeFunction";           return SPV_OP_TYPE_FUNCTION, true;
  case "OpTypeForwardPointer";     return SPV_OP_TYPE_FORWARD_POINTER, true;
  case "OpConstantTrue";           return SPV_OP_CONSTANT_TRUE, true;
  case "OpConstantFalse";          return SPV_OP_CONSTANT_FALSE, true;
  case "OpConstant";               return SPV_OP_CONSTANT, true;
  case "OpConstantNull";           return SPV_OP_CONSTANT_NULL, true;
  case "OpSpecConstantTrue";       return SPV_OP_SPEC_CONSTANT_TRUE, true;
  case "OpSpecConstantFalse";      return SPV_OP_SPEC_CONSTANT_FALSE, true;
  case "OpSpecConstant";           return SPV_OP_SPEC_CONSTANT, true;
  case "OpSpecConstantComposite";  return SPV_OP_SPEC_CONSTANT_COMPOSITE, true;
  case "OpVariable";               return SPV_OP_VARIABLE, true;
  case "OpFunction";               return SPV_OP_FUNCTION, true;
  case "OpLabel";                  return SPV_OP_LABEL, true;
  case "OpFunctionEnd";            return SPV_OP_FUNCTION_END, true;
  case "OpLoad";                   return SPV_OP_LOAD, true;
  case "OpStore";                  return SPV_OP_STORE, true;
  case "OpAccessChain";            return SPV_OP_ACCESS_CHAIN, true;
  case "OpCompositeConstruct";     return SPV_OP_COMPOSITE_CONSTRUCT, true;
  case "OpCompositeExtract";       return SPV_OP_COMPOSITE_EXTRACT, true;
  case "OpVectorShuffle";          return SPV_OP_VECTOR_SHUFFLE, true;
  case "OpBranch";                 return SPV_OP_BRANCH, true;
  case "OpBranchConditional";      return SPV_OP_BRANCH_CONDITIONAL, true;
  case "OpSwitch";                 return SPV_OP_SWITCH, true;
  case "OpSelectionMerge";         return SPV_OP_SELECTION_MERGE, true;
  case "OpLoopMerge";              return SPV_OP_LOOP_MERGE, true;
  case "OpReturn";                 return SPV_OP_RETURN, true;
  case "OpKill";                   return SPV_OP_KILL, true;
  case "OpUnreachable";            return SPV_OP_UNREACHABLE, true;
  case "OpSampledImage";           return SPV_OP_SAMPLE_IMAGE, true;
  case "OpImageSampleImplicitLod"; return SPV_OP_IMAGE_SAMPLE_IMPLICIT_LOD, true;
  case "OpImageWrite";             return SPV_OP_IMAGE_WRITE, true;
  case "OpSelect";                 return SPV_OP_SELECT, true;
  case "OpFNegate";                return SPV_OP_FNEGATE, true;
  case "OpSNegate";                return SPV_OP_SNEGATE, true;
  case "OpIAdd";                   return SPV_OP_IADD, true;
  case "OpISub";                   return SPV_OP_ISUB, true;
  case "OpIMul";                   return SPV_OP_IMUL, true;
  case "OpSDiv";                   return SPV_OP_SDIV, true;
  case "OpUDiv";                   return SPV_OP_UDIV, true;
  case "OpSMod";                   return SPV_OP_SMOD, true;
  case "OpUMod";                   return SPV_OP_UMOD, true;
  case "OpFAdd";                   return SPV_OP_FADD, true;
  case "OpFSub";                   return SPV_OP_FSUB, true;
  case "OpFMul";                   return SPV_OP_FMUL, true;
  case "OpFDiv";                   return SPV_OP_FDIV, true;
  case "OpFRem";                   return SPV_OP_FREM, true;
  case "OpBitcast";                return SPV_OP_BITCAST, true;
  case "OpFConvert";               return SPV_OP_FCONVERT, true;
  case "OpSConvert";               return SPV_OP_SCONVERT, true;
  case "OpUConvert";               return SPV_OP_UCONVERT, true;
  case "OpConvertFToS";            return SPV_OP_CONVERT_F_TO_S, true;
  case "OpConvertFToU";            return SPV_OP_CONVERT_F_TO_U, true;
  case "OpConvertSToF";            return SPV_OP_CONVERT_S_TO_F, true;
  case "OpConvertUToF";            return SPV_OP_CONVERT_U_TO_F, true;
  case "OpNot";                    return SPV_OP_NOT, true;
  case "OpLogicalNot";             return SPV_OP_LOGICAL_NOT, true;
  case "OpBitwiseOr";              return SPV_OP_BITWISE_OR, true;
  case "OpBitwiseAnd";             return SPV_OP_BITWISE_AND, true;
  case "OpBitwiseXor";             return SPV_OP_BITWISE_XOR, true;
  case "OpShiftLeftLogical";       return SPV_OP_SHIFT_LEFT_LOGICAL, true;
  case "OpShiftRightLogical";      return SPV_OP_SHIFT_RIGHT_LOGICAL, true;
  case "OpShiftRightArithmetic";   return SPV_OP_SHIFT_RIGHT_ARITHMETIC, true;
  case "OpIEqual";                 return SPV_OP_IEQUAL, true;
  case "OpINotEqual";              return SPV_OP_INOT_EQUAL, true;
  case "OpFOrdEqual";              return SPV_OP_FORD_EQUAL, true;
  case "OpFOrdNotEqual";           return SPV_OP_FORD_NOT_EQUAL, true;
  case "OpFOrdLessThan";           return SPV_OP_FORD_LESS_THAN, true;
  case "OpFOrdLessThanEqual";      return SPV_OP_FORD_LESS_THAN_EQUAL, true;
  case "OpFOrdGreaterThan";        return SPV_OP_FORD_GREATER_THAN, true;
  case "OpFOrdGreaterThanEqual";   return SPV_OP_FORD_GREATER_THAN_EQUAL, true;
  case "OpSLessThan";              return SPV_OP_SLESS_THAN, true;
  case "OpSLessThanEqual";         return SPV_OP_SLESS_THAN_EQUAL, true;
  case "OpSGreaterThan";           return SPV_OP_SGREATER_THAN, true;
  case "OpSGreaterThanEqual";      return SPV_OP_SGREATER_THAN_EQUAL, true;
  case "OpULessThan";              return SPV_OP_ULESS_THAN, true;
  case "OpULessThanEqual";         return SPV_OP_ULESS_THAN_EQUAL, true;
  case "OpUGreaterThan";           return SPV_OP_UGREATER_THAN, true;
  case "OpUGreaterThanEqual";      return SPV_OP_UGREATER_THAN_EQUAL, true;
  case "OpMatrixTimesVector";      return SPV_OP_MATRIX_TIMES_VECTOR, true;
  case "OpAtomicIAdd";             return SPV_OP_ATOMIC_IADD, true;
  case "OpAtomicExchange";         return SPV_OP_ATOMIC_EXCHANGE, true;
  case "OpAtomicCompareExchange";  return SPV_OP_ATOMIC_COMPARE_EXCHANGE, true;
  case "OpEmitMeshTasksEXT";       return SPV_OP_EMIT_MESH_TASKS_EXT, true;
  case "OpDecorate";               return SPV_OP_DECORATE, true;
  case "OpMemberDecorate";         return SPV_OP_MEMBER_DECORATE, true;
  }
  return 0, false;
}

spv_lookup_capability :: (name: string) -> (u32, bool) {
  if name == {
  case "Shader";                             return SPV_CAPABILITY_SHADER, true;
  case "MeshShadingEXT";                     return SPV_CAPABILITY_MESH_SHADING_EXT, true;
  case "Int8";                               return SPV_CAPABILITY_INT8, true;
  case "Int16";                              return SPV_CAPABILITY_INT16, true;
  case "Int64";                              return SPV_CAPABILITY_INT64, true;
  case "Float16";                            return SPV_CAPABILITY_FLOAT16, true;
  case "StorageBuffer8BitAccess";            return SPV_CAPABILITY_STORAGE_BUFFER8_BIT_ACCESS, true;
  case "StorageBuffer16BitAccess";           return SPV_CAPABILITY_STORAGE_BUFFER16_BIT_ACCESS, true;
  case "StorageImageWriteWithoutFormat";     return SPV_CAPABILITY_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT, true;
  case "PhysicalStorageBufferAddresses";     return SPV_CAPABILITY_PHYSICAL_STORAGE_BUFFER_ADDRESSES, true;
  }
  return 0, false;
}

spv_lookup_addressing_model :: (name: string) -> (u32, bool) {
  if name == "Logical" return SPV_ADDRESSING_MODEL_LOGICAL, true;
  if name == "PhysicalStorageBuffer64" return SPV_ADDRESSING_MODEL_PHYSICAL_STORAGE_BUFFER_64, true;
  return 0, false;
}

spv_lookup_memory_model :: (name: string) -> (u32, bool) {
  if name == "GLSL450" return SPV_MEMORY_MODEL_GLSL450, true;
  return 0, false;
}

spv_lookup_execution_model :: (name: string) -> (u32, bool) {
  if name == "Vertex" return SPV_EXECUTION_MODEL_VERTEX, true;
  if name == "Fragment" return SPV_EXECUTION_MODEL_FRAGMENT, true;
  if name == "GLCompute" return SPV_EXECUTION_MODEL_GLCOMPUTE, true;
  if name == "TaskEXT" return SPV_EXECUTION_MODEL_TASK_EXT, true;
  if name == "MeshEXT" return SPV_EXECUTION_MODEL_MESH_EXT, true;
  return 0, false;
}

spv_lookup_execution_mode :: (name: string) -> (u32, bool) {
  if name == "OriginUpperLeft" return SPV_EXECUTION_MODE_ORIGIN_UPPER_LEFT, true;
  if name == "LocalSize" return SPV_EXECUTION_MODE_LOCAL_SIZE, true;
  return 0, false;
}

spv_lookup_source_language :: (name: string) -> (u32, bool) {
  if name == "Unknown" return SPV_SOURCE_LANGUAGE_UNKNOWN, true;
  return 0, false;
}

spv_lookup_decoration :: (name: string) -> (u32, bool) {
  if name == {
  case "BuiltIn";      return SPV_DECORATION_BUILTIN, true;
  case "Location";     return SPV_DECORATION_LOCATION, true;
  case "Binding";      return SPV_DECORATION_BINDING, true;
  case "DescriptorSet"; return SPV_DECORATION_DESCRIPTOR_SET, true;
  case "SpecId";       return SPV_DECORATION_SPEC_ID, true;
  case "RowMajor";     return SPV_DECORATION_ROW_MAJOR, true;
  case "ColMajor";     return SPV_DECORATION_COL_MAJOR, true;
  case "ArrayStride";  return SPV_DECORATION_ARRAY_STRIDE, true;
  case "MatrixStride"; return SPV_DECORATION_MATRIX_STRIDE, true;
  case "Block";        return SPV_DECORATION_BLOCK, true;
  case "Offset";       return SPV_DECORATION_OFFSET, true;
  case "NonWritable";  return SPV_DECORATION_NON_WRITABLE, true;
  }
  return 0, false;
}

spv_lookup_builtin :: (name: string) -> (u32, bool) {
  if name == {
  case "Position";             return SPV_BUILTIN_POSITION, true;
  case "FragCoord";            return SPV_BUILTIN_FRAG_COORD, true;
  case "VertexIndex";          return SPV_BUILTIN_VERTEX_INDEX, true;
  case "InstanceIndex";        return SPV_BUILTIN_INSTANCE_INDEX, true;
  case "GlobalInvocationId";   return SPV_BUILTIN_GLOBAL_INVOCATION_ID, true;
  case "LocalInvocationId";    return SPV_BUILTIN_LOCAL_INVOCATION_ID, true;
  case "WorkgroupId";          return SPV_BUILTIN_WORKGROUP_ID, true;
  case "LocalInvocationIndex"; return SPV_BUILTIN_LOCAL_INVOCATION_INDEX, true;
  }
  return 0, false;
}

spv_lookup_storage_class :: (name: string) -> (u32, bool) {
  if name == {
  case "UniformConstant";      return SPV_STORAGE_CLASS_UNIFORM_CONSTANT, true;
  case "Input";                return SPV_STORAGE_CLASS_INPUT, true;
  case "Uniform";              return SPV_STORAGE_CLASS_UNIFORM, true;
  case "Output";               return SPV_STORAGE_CLASS_OUTPUT, true;
  case "Function";             return SPV_STORAGE_CLASS_FUNCTION, true;
  case "StorageBuffer";        return SPV_STORAGE_CLASS_STORAGE_BUFFER, true;
  case "PhysicalStorageBuffer"; return SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER, true;
  }
  return 0, false;
}

spv_lookup_function_control :: (name: string) -> (u32, bool) {
  if name == "None" return 0, true;
  return 0, false;
}

spv_lookup_selection_control :: (name: string) -> (u32, bool) {
  if name == "None" return 0, true;
  return 0, false;
}

spv_lookup_loop_control :: (name: string) -> (u32, bool) {
  if name == "None" return 0, true;
  return 0, false;
}

spv_lookup_dim :: (name: string) -> (u32, bool) {
  if name == "2D" return SPV_DIM_2D, true;
  if name == "3D" return SPV_DIM_3D, true;
  return 0, false;
}

spv_lookup_image_format :: (name: string) -> (u32, bool) {
  if name == "Unknown" return SPV_IMAGE_FORMAT_UNKNOWN, true;
  return 0, false;
}

spv_lookup_glsl_extinst :: (name: string) -> (u32, bool) {
  if name == {
  case "Floor";      return SPV_GLSL_STD_450_FLOOR, true;
  case "FMin";       return SPV_GLSL_STD_450_FMIN, true;
  case "UMin";       return SPV_GLSL_STD_450_UMIN, true;
  case "FMax";       return SPV_GLSL_STD_450_FMAX, true;
  case "FAbs";       return SPV_GLSL_STD_450_FABS, true;
  case "Sqrt";       return SPV_GLSL_STD_450_SQRT, true;
  case "Exp";        return SPV_GLSL_STD_450_EXP, true;
  case "Sin";        return SPV_GLSL_STD_450_SIN, true;
  case "Cos";        return SPV_GLSL_STD_450_COS, true;
  case "Fract";      return SPV_GLSL_STD_450_FRACT, true;
  case "FClamp";     return SPV_GLSL_STD_450_FCLAMP, true;
  case "Step";       return SPV_GLSL_STD_450_STEP, true;
  case "FMix";       return SPV_GLSL_STD_450_FMIX, true;
  case "Reflect";    return SPV_GLSL_STD_450_REFLECT, true;
  case "Pow";        return SPV_GLSL_STD_450_POW, true;
  case "SmoothStep"; return SPV_GLSL_STD_450_SMOOTHSTEP, true;
  case "Length";     return SPV_GLSL_STD_450_LENGTH, true;
  case "Normalize";  return SPV_GLSL_STD_450_NORMALIZE, true;
  }
  return 0, false;
}

SPV_OP_SOURCE                  :: 3;
SPV_OP_NAME                    :: 5;
SPV_OP_MEMBER_NAME             :: 6;
SPV_OP_STRING                  :: 7;
SPV_OP_LINE                    :: 8;
SPV_OP_EXTENSION               :: 10;
SPV_OP_EXT_INST_IMPORT         :: 11;
SPV_OP_EXT_INST                :: 12;
SPV_OP_MEMORY_MODEL            :: 14;
SPV_OP_ENTRY_POINT             :: 15;
SPV_OP_EXECUTION_MODE          :: 16;
SPV_OP_CAPABILITY              :: 17;
SPV_OP_TYPE_VOID               :: 19;
SPV_OP_TYPE_BOOL               :: 20;
SPV_OP_TYPE_INT                :: 21;
SPV_OP_TYPE_FLOAT              :: 22;
SPV_OP_TYPE_VECTOR             :: 23;
SPV_OP_TYPE_MATRIX             :: 24;
SPV_OP_TYPE_IMAGE              :: 25;
SPV_OP_TYPE_SAMPLER            :: 26;
SPV_OP_TYPE_SAMPLED_IMAGE      :: 27;
SPV_OP_TYPE_ARRAY              :: 28;
SPV_OP_TYPE_RUNTIME_ARRAY      :: 29;
SPV_OP_TYPE_STRUCT             :: 30;
SPV_OP_TYPE_POINTER            :: 32;
SPV_OP_TYPE_FUNCTION           :: 33;
SPV_OP_TYPE_FORWARD_POINTER    :: 39;
SPV_OP_CONSTANT_TRUE           :: 41;
SPV_OP_CONSTANT_FALSE          :: 42;
SPV_OP_CONSTANT                :: 43;
SPV_OP_CONSTANT_NULL           :: 46;
SPV_OP_SPEC_CONSTANT_TRUE      :: 48;
SPV_OP_SPEC_CONSTANT_FALSE     :: 49;
SPV_OP_SPEC_CONSTANT           :: 50;
SPV_OP_SPEC_CONSTANT_COMPOSITE :: 51;
SPV_OP_FUNCTION                :: 54;
SPV_OP_FUNCTION_END            :: 56;
SPV_OP_VARIABLE                :: 59;
SPV_OP_LOAD                    :: 61;
SPV_OP_STORE                   :: 62;
SPV_OP_ACCESS_CHAIN            :: 65;
SPV_OP_DECORATE                :: 71;
SPV_OP_MEMBER_DECORATE         :: 72;
SPV_OP_VECTOR_SHUFFLE          :: 79;
SPV_OP_COMPOSITE_CONSTRUCT     :: 80;
SPV_OP_COMPOSITE_EXTRACT       :: 81;
SPV_OP_SAMPLE_IMAGE            :: 86;
SPV_OP_IMAGE_SAMPLE_IMPLICIT_LOD :: 87;
SPV_OP_IMAGE_WRITE             :: 99;
SPV_OP_CONVERT_F_TO_U          :: 109;
SPV_OP_CONVERT_F_TO_S          :: 110;
SPV_OP_CONVERT_S_TO_F          :: 111;
SPV_OP_CONVERT_U_TO_F          :: 112;
SPV_OP_UCONVERT                :: 113;
SPV_OP_SCONVERT                :: 114;
SPV_OP_FCONVERT                :: 115;
SPV_OP_SNEGATE                 :: 126;
SPV_OP_FNEGATE                 :: 127;
SPV_OP_IADD                    :: 128;
SPV_OP_FADD                    :: 129;
SPV_OP_ISUB                    :: 130;
SPV_OP_FSUB                    :: 131;
SPV_OP_IMUL                    :: 132;
SPV_OP_FMUL                    :: 133;
SPV_OP_UDIV                    :: 134;
SPV_OP_SDIV                    :: 135;
SPV_OP_FDIV                    :: 136;
SPV_OP_UMOD                    :: 137;
SPV_OP_SMOD                    :: 139;
SPV_OP_FREM                    :: 140;
SPV_OP_MATRIX_TIMES_VECTOR     :: 145;
SPV_OP_LOGICAL_NOT             :: 168;
SPV_OP_SELECT                  :: 169;
SPV_OP_IEQUAL                  :: 170;
SPV_OP_INOT_EQUAL              :: 171;
SPV_OP_UGREATER_THAN           :: 172;
SPV_OP_SGREATER_THAN           :: 173;
SPV_OP_UGREATER_THAN_EQUAL     :: 174;
SPV_OP_SGREATER_THAN_EQUAL     :: 175;
SPV_OP_ULESS_THAN              :: 176;
SPV_OP_SLESS_THAN              :: 177;
SPV_OP_ULESS_THAN_EQUAL        :: 178;
SPV_OP_SLESS_THAN_EQUAL        :: 179;
SPV_OP_FORD_EQUAL              :: 180;
SPV_OP_FORD_NOT_EQUAL          :: 182;
SPV_OP_FORD_LESS_THAN          :: 184;
SPV_OP_FORD_GREATER_THAN       :: 186;
SPV_OP_FORD_LESS_THAN_EQUAL    :: 188;
SPV_OP_FORD_GREATER_THAN_EQUAL :: 190;
SPV_OP_SHIFT_RIGHT_LOGICAL     :: 194;
SPV_OP_SHIFT_RIGHT_ARITHMETIC  :: 195;
SPV_OP_SHIFT_LEFT_LOGICAL      :: 196;
SPV_OP_BITWISE_OR              :: 197;
SPV_OP_BITWISE_XOR             :: 198;
SPV_OP_BITWISE_AND             :: 199;
SPV_OP_NOT                     :: 200;
SPV_OP_BITCAST                 :: 124;
SPV_OP_ATOMIC_EXCHANGE         :: 229;
SPV_OP_ATOMIC_COMPARE_EXCHANGE :: 230;
SPV_OP_ATOMIC_IADD             :: 234;
SPV_OP_LOOP_MERGE              :: 246;
SPV_OP_SELECTION_MERGE         :: 247;
SPV_OP_LABEL                   :: 248;
SPV_OP_BRANCH                  :: 249;
SPV_OP_BRANCH_CONDITIONAL      :: 250;
SPV_OP_SWITCH                  :: 251;
SPV_OP_KILL                    :: 252;
SPV_OP_RETURN                  :: 253;
SPV_OP_UNREACHABLE             :: 255;
SPV_OP_EMIT_MESH_TASKS_EXT     :: 5294;
SPV_OP_SET_MESH_OUTPUTS_EXT    :: 5295;

SPV_CAPABILITY_SHADER                          :: 1;
SPV_CAPABILITY_FLOAT16                         :: 9;
SPV_CAPABILITY_INT16                           :: 22;
SPV_CAPABILITY_INT64                           :: 11;
SPV_CAPABILITY_INT8                            :: 39;
SPV_CAPABILITY_STORAGE_BUFFER16_BIT_ACCESS     :: 4433;
SPV_CAPABILITY_STORAGE_BUFFER8_BIT_ACCESS      :: 4448;
SPV_CAPABILITY_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT :: 56;
SPV_CAPABILITY_PHYSICAL_STORAGE_BUFFER_ADDRESSES :: 5347;
SPV_CAPABILITY_MESH_SHADING_EXT                :: 5283;

SPV_ADDRESSING_MODEL_LOGICAL                   :: 0;
SPV_ADDRESSING_MODEL_PHYSICAL_STORAGE_BUFFER_64 :: 5348;
SPV_MEMORY_MODEL_GLSL450                       :: 1;

SPV_EXECUTION_MODEL_VERTEX                     :: 0;
SPV_EXECUTION_MODEL_FRAGMENT                   :: 4;
SPV_EXECUTION_MODEL_GLCOMPUTE                  :: 5;
SPV_EXECUTION_MODEL_TASK_EXT                   :: 5364;
SPV_EXECUTION_MODEL_MESH_EXT                   :: 5365;

SPV_EXECUTION_MODE_ORIGIN_UPPER_LEFT           :: 7;
SPV_EXECUTION_MODE_LOCAL_SIZE                  :: 17;
SPV_EXECUTION_MODE_OUTPUT_VERTICES             :: 26;
SPV_EXECUTION_MODE_OUTPUT_PRIMITIVES_EXT       :: 5270;
SPV_EXECUTION_MODE_OUTPUT_TRIANGLES_EXT        :: 5298;

SPV_SOURCE_LANGUAGE_UNKNOWN                    :: 0;

SPV_DECORATION_SPEC_ID                         :: 1;
SPV_DECORATION_BLOCK                           :: 2;
SPV_DECORATION_ROW_MAJOR                       :: 4;
SPV_DECORATION_COL_MAJOR                       :: 5;
SPV_DECORATION_ARRAY_STRIDE                    :: 6;
SPV_DECORATION_MATRIX_STRIDE                   :: 7;
SPV_DECORATION_BUILTIN                         :: 11;
SPV_DECORATION_NON_WRITABLE                    :: 24;
SPV_DECORATION_LOCATION                        :: 30;
SPV_DECORATION_BINDING                         :: 33;
SPV_DECORATION_DESCRIPTOR_SET                  :: 34;
SPV_DECORATION_OFFSET                          :: 35;

SPV_BUILTIN_POSITION                           :: 0;
SPV_BUILTIN_WORKGROUP_ID                       :: 26;
SPV_BUILTIN_LOCAL_INVOCATION_ID                :: 27;
SPV_BUILTIN_GLOBAL_INVOCATION_ID               :: 28;
SPV_BUILTIN_LOCAL_INVOCATION_INDEX             :: 29;
SPV_BUILTIN_FRAG_COORD                         :: 15;
SPV_BUILTIN_VERTEX_INDEX                       :: 42;
SPV_BUILTIN_INSTANCE_INDEX                     :: 43;
SPV_BUILTIN_PRIMITIVE_TRIANGLE_INDICES_EXT     :: 5296;

SPV_STORAGE_CLASS_UNIFORM_CONSTANT             :: 0;
SPV_STORAGE_CLASS_INPUT                        :: 1;
SPV_STORAGE_CLASS_UNIFORM                      :: 2;
SPV_STORAGE_CLASS_OUTPUT                       :: 3;
SPV_STORAGE_CLASS_FUNCTION                     :: 7;
SPV_STORAGE_CLASS_STORAGE_BUFFER               :: 12;
SPV_STORAGE_CLASS_TASK_PAYLOAD_WORKGROUP_EXT   :: 5402;
SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER      :: 5349;

SPV_DIM_2D                                     :: 1;
SPV_DIM_3D                                     :: 2;
SPV_IMAGE_FORMAT_UNKNOWN                       :: 0;

SPV_MEMORY_ACCESS_ALIGNED_MASK                 :: 2;

SPV_GLSL_STD_450_FABS                          :: 4;
SPV_GLSL_STD_450_FLOOR                         :: 8;
SPV_GLSL_STD_450_FRACT                         :: 10;
SPV_GLSL_STD_450_SIN                           :: 13;
SPV_GLSL_STD_450_COS                           :: 14;
SPV_GLSL_STD_450_POW                           :: 26;
SPV_GLSL_STD_450_EXP                           :: 27;
SPV_GLSL_STD_450_SQRT                          :: 31;
SPV_GLSL_STD_450_FMIN                          :: 37;
SPV_GLSL_STD_450_UMIN                          :: 38;
SPV_GLSL_STD_450_FMAX                          :: 40;
SPV_GLSL_STD_450_FCLAMP                        :: 43;
SPV_GLSL_STD_450_FMIX                          :: 46;
SPV_GLSL_STD_450_STEP                          :: 48;
SPV_GLSL_STD_450_SMOOTHSTEP                    :: 49;
SPV_GLSL_STD_450_LENGTH                        :: 66;
SPV_GLSL_STD_450_NORMALIZE                     :: 69;
SPV_GLSL_STD_450_REFLECT                       :: 71;
