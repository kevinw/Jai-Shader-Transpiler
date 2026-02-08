// TODOS:
// Add the different types of Vectors and implement the 'Component Comparison' set of GLSL functions
// Translation for more advanced jai features
// Add the differet types of Samplers
// Add support for out parameters
// Add support for structs and arrays
// Add support for Geometry and Compute Shaders

// Think about:
// Changing GLSL version without changing module code.
// Adding #line directive for shader debuggers to point back at the original Jai file

VERBOSE      :: false;
DEBUG_OUTDIR :: ".generated_shaders";

#load "backend_shared.jai";
#load "glsl_backend.jai";
#load "hlsl_backend.jai";
#load "metal_backend.jai";

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    output_shaders: bool;
    currently_waiting_contexts: [..] Shader_Write_Context;
}

get_plugin :: () -> *Jai_To_Shader_Plugin {
  p := New(Jai_To_Shader_Plugin);

  p.message = convert_procs;

  return p;
}

convert_procs :: (p: *Metaprogram_Plugin, message: *Message) {
  plugin := cast(*Jai_To_Shader_Plugin) p;

  if message.kind == {
    case .TYPECHECKED; {
      tc := cast(*Message_Typechecked) message;
      for tc.procedure_bodies {
        // Has a @glsl or @vulkan Note
        if proc_has_note(it.expression.header, "glsl") || proc_has_note(it.expression.header, "vulkan") {
          array_add(*plugin.currently_waiting_contexts, create_shader_write_context(.GLSL, it.expression));
        }
        
        // Has a @hlsl Note
        if proc_has_note(it.expression.header, "hlsl") {
          array_add(*plugin.currently_waiting_contexts, create_shader_write_context(.HLSL, it.expression));
        }

        // Has a @metal Note
        if proc_has_note(it.expression.header, "metal") {
          array_add(*plugin.currently_waiting_contexts, create_shader_write_context(.METAL, it.expression));
        }

        // Has no language note, but has a shader-stage note.
        if !(proc_has_note(it.expression.header, "glsl") ||
             proc_has_note(it.expression.header, "vulkan") ||
             proc_has_note(it.expression.header, "hlsl") ||
             proc_has_note(it.expression.header, "metal")) {
          if proc_has_note(it.expression.header, "vertex_shader") ||
             proc_has_note(it.expression.header, "fragment_shader") ||
             proc_has_note(it.expression.header, "compute_shader") {
            compiler_report("Jai Shader Transpiler: No Tag that maps to a language. Add @glsl/@vulkan, @hlsl, or @metal to specify the language",
                            make_location(it.expression.header));
          }
        }
      }
    }
    
    case .PHASE; {
      phase := cast(*Message_Phase) message;
      if phase.phase == .TYPECHECKED_ALL_WE_CAN {
        for * ctx: plugin.currently_waiting_contexts {
          
          s: string;
          if ctx.type == {
            case .Vertex;   #through;
            case .Fragment; #through;
            case .Compute;
              s = write_shader(ctx, ctx.main_fn);
              
            case; compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader",
                            make_location(ctx.main_fn.header));
          }

          add_build_string(s, p.workspace);
          if plugin.output_shaders {
            ext := tprint("%", ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, ctx.name, ext);
            file_source := write_shader_code(ctx, ctx.main_fn, as_jai_string=false);
            ok := write_entire_file(filename, file_source);
            if !ok {
              log_error("Error writing file to '%'", filename);
            } else {
              #if VERBOSE log("Transpiled Jai to %", filename);
            }
          }
          remove ctx;
        }
      }
    }
    
    case .COMPLETE; {
      if plugin.currently_waiting_contexts.count != 0 {
        compiler_report("Jai Shader Transpiler: Something went wrong while converting Jai Shaders to shader code.\nThere's some functions that have not yet been transpiled, that a shader is waiting on. This is not good.");
      }
      array_reset(*plugin.currently_waiting_contexts);
    }
  }
}

write_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  // log("Converting % Shader: %", ctx.type, node.header.name);
  
  if ctx.language == {
    case .GLSL;  return write_glsl_shader (ctx, node, ctx.type);
    case .HLSL;  return write_hlsl_shader (ctx, node, ctx.type);
    case .METAL; return write_metal_shader(ctx, node, ctx.type);
  }
  
  return "";
}

write_procedure_call :: (ctx: *Shader_Write_Context, node: *String_Builder, pc: *Code_Procedure_Call) {
  if ctx.language == {
    case .GLSL;  print_glsl_procedure_call (ctx, node, pc);
    case .HLSL;  print_hlsl_procedure_call (ctx, node, pc);
    case .METAL; print_metal_procedure_call(ctx, node, pc);
  }
}

write_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, called_fn: *Code_Procedure_Header) {
  if ctx.language == {
    case .GLSL;  print_glsl_function (ctx, sb, called_fn);
    case .HLSL;  print_hlsl_function (ctx, sb, called_fn);
    case .METAL; print_metal_function(ctx, sb, called_fn);
  }
}

write_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  if ctx.language == {
    case .GLSL;  return write_glsl_shader_code (ctx, node, as_jai_string=as_jai_string);
    case .HLSL;  return write_hlsl_shader_code (ctx, node, as_jai_string=as_jai_string);
    case .METAL; return write_metal_shader_code(ctx, node, as_jai_string=as_jai_string);
  }

  return "";
}




// Only function that has to be called from a backend

handle_custom_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  name := cast(*Code_Ident) pc.procedure_expression;
  
  // Make sure we're not writing the function again
  found := false;
  for ctx.functions if it.name == name.name found = true;
  if !found {
    called_function := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
    
    function_code: String_Builder;
    write_function(ctx, *function_code, called_function);
      
    array_add(*ctx.functions, .{
      prototype=called_function,
      name=name.name,
      code=builder_to_string(*function_code),
    });
  }
}

// @whatthefuckisthis im 99% sure there's a simpler way of converting an int to a string directly.
// or atleast printing it as a character, because the first switch is.... yikes
operator_string :: (op: Operator_Type) -> string {
  if op == {
    case cast(Operator_Type) #char "="; return "=";
    case cast(Operator_Type) #char "<"; return "<";
    case cast(Operator_Type) #char "?"; return "?";
    case cast(Operator_Type) #char ">"; return ">";
    case cast(Operator_Type) #char "!"; return "!";
    case cast(Operator_Type) #char "+"; return "+";
    case cast(Operator_Type) #char "-"; return "-";
    case cast(Operator_Type) #char "*"; return "*";
    case cast(Operator_Type) #char "/"; return "/";
    case cast(Operator_Type) #char "%"; return "%";
    case cast(Operator_Type) #char "~"; return "~";
    case cast(Operator_Type) #char "."; return ".";
  }

  if op == {
    case .PLUS_ASSIGN; return "+=";
    case .MINUS_ASSIGN; return "-=";
    case .TIMES_ASSIGN; return "*=";
    case .DIV_ASSIGN; return "/=";
    case .MOD_ASSIGN; return "%=";
    case .IS_EQUAL; return "==";
    case .IS_NOT_EQUAL; return "!=";
    case .LOGICAL_AND; return "&&";
    case .LOGICAL_OR; return "||";
    case .LESS_OR_EQUAL; return "<=";
    case .GREATER_OR_EQUAL; return ">=";
    
    case .SHIFT_LEFT; return "<<";
    case .SHIFT_RIGHT; return ">>";
    case .ARRAY_SUBSCRIPT; return "[]";
    
    // I don't think operators below this are supported in glsl
    // But this can stay just incase...
    // case .ROTATE_LEFT; return "<<<";
    // case .ROTATE_RIGHT; return ">>>";
    // case .SHIFT_LEFT_ASSIGN; return "<<=";
    // case .SHIFT_RIGHT_ASSIGN; return ">>=";
    // case .ROTATE_LEFT_ASSIGN; return "<<<=";
    // case .ROTATE_RIGHT_ASSIGN; return ">>>=";
    // case .BITWISE_AND_ASSIGN; return "&=";
    // case .BITWISE_OR_ASSIGN; return "|=";
    // case .BITWISE_XOR_ASSIGN; return "^=";
    // case .LOGICAL_AND_ASSIGN; return "&&=";
    // case .LOGICAL_OR_ASSIGN; return "||=";
    
    case; return "<operator_not_supported>";
  }
}

//~

SamplerState :: #type,distinct s32;
Texture1D :: struct { Sample: #type (sampler: SamplerState, tex_coord: float32) -> Vector4; };
Texture2D :: struct { Sample: #type (sampler: SamplerState, tex_coord: Vector3) -> Vector4; };
Texture3D :: struct { Sample: #type (sampler: SamplerState, tex_coord: Vector3) -> Vector4; };

IVector2 :: struct { x, y: s32; }
IVector3 :: struct { x, y, z: s32; }
IVector4 :: struct { x, y, z, w: s32; }
UVector2 :: struct { x, y: u32; }
UVector3 :: struct { x, y, z: u32; }
UVector4 :: struct { x, y, z, w: u32; }
BVector2 :: struct { x, y: bool; }
BVector3 :: struct { x, y, z: bool; }
BVector4 :: struct { x, y, z, w: bool; }

Sampler1D :: #type,distinct s32;
Sampler2D :: #type,distinct s32;
Sampler3D :: #type,distinct s32;

Shader_Type :: enum {
  Vertex;
  Fragment;
  Compute;
}

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
  metal_use_jai_radians: bool;
  metal_use_jai_degrees: bool;
}

node_is_fragment_shader :: (node: *Code_Procedure_Header) -> bool {
  for node.notes if it.text == "fragment_shader" return true;
  return false;
}

member_has_note :: (member: *Type_Info_Struct_Member, note: string) -> bool {
  for member.notes if it == note return true;
  return false;
}

member_has_note_contains :: (member: *Type_Info_Struct_Member, note_fragment: string) -> bool {
  for member.notes {
    found, _ := contains(it, note_fragment);
    if found return true;
  }
  return false;
}

member_is_stage_builtin :: (member: *Type_Info_Struct_Member) -> bool {
  if member_has_note_contains(member, "position") return true;
  if member_has_note_contains(member, "frag_coord") return true;
  if member_has_note_contains(member, "frag_depth") return true;
  if member_has_note_contains(member, "vertex_id") return true;
  if member_has_note_contains(member, "instance_id") return true;
  if member_has_note_contains(member, "front_facing") return true;
  if member_has_note_contains(member, "point_size") return true;
  if member_has_note_contains(member, "sample_id") return true;
  if member_has_note_contains(member, "sample_mask") return true;
  return false;
}

member_get_compute_builtin_note :: (member: *Type_Info_Struct_Member) -> (string, bool) {
  for member.notes {
    found, _ := contains(it, "thread_position_in_grid");
    if found return "thread_position_in_grid", true;
    found, _ = contains(it, "thread_position_in_threadgroup");
    if found return "thread_position_in_threadgroup", true;
    found, _ = contains(it, "threadgroup_position_in_grid");
    if found return "threadgroup_position_in_grid", true;
    found, _ = contains(it, "thread_index_in_threadgroup");
    if found return "thread_index_in_threadgroup", true;
  }
  return "", false;
}

member_get_note_suffix :: (member: *Type_Info_Struct_Member, prefix_check: string) -> (string, bool) {
  for member.notes if begins_with(it, prefix_check) {
    ret: string;
    ret.data = it.data + prefix_check.count;
    ret.count = it.count - prefix_check.count;
    return ret, true;
  }
  return "", false;
}

declaration_get_note_suffix :: (decl: *Code_Declaration, prefix_check: string) -> (string, bool) {
  for decl.notes if begins_with(it.text, prefix_check) {
    ret: string;
    ret.data = it.text.data + prefix_check.count;
    ret.count = it.text.count - prefix_check.count;
    return ret, true;
  }
  return "", false;
}

declaration_is_parameter_using :: (header: *Code_Procedure_Header, decl: *Code_Declaration) -> bool {
  for header.parameter_usings {
    if !it.expression || it.expression.kind != .IDENT continue;
    ident := cast(*Code_Ident) it.expression;
    if ident.resolved_declaration == decl return true;
    if ident.name == decl.name return true;
  }
  return false;
}


#import "Basic";
#import "Compiler";
PP :: #import "Program_Print";
#import "String";
#import "Math";
#import "Hash_Table";

append :: inline (builder: *String_Builder, strings: ..string) {
  for strings {
    append(builder, it.data, it.count);
  }
}

#scope_file

#import "File";

proc_has_note :: (node: *Code_Procedure_Header, note: string) -> bool {
  for node.notes if it.text == note return true;
  return false;
}

create_shader_write_context :: (language: Shader_Language, proc: *Code_Procedure_Body) -> Shader_Write_Context {
    shader_type: Shader_Type;
    glsl_target: GLSL_Target = ifx proc_has_note(proc.header, "vulkan") then .VULKAN else .OPENGL;
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
    };
}
