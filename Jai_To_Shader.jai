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
        // Has a @glsl Note
        if proc_has_note(it.expression.header, "glsl") {
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
             proc_has_note(it.expression.header, "hlsl") ||
             proc_has_note(it.expression.header, "metal")) {
          if proc_has_note(it.expression.header, "vertex_shader") ||
             proc_has_note(it.expression.header, "fragment_shader") ||
             proc_has_note(it.expression.header, "compute_shader") {
            compiler_report("Jai Shader Transpiler: No Tag that maps to a language. Add @glsl, @hlsl, or @metal to specify the language",
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
            filename := tprint("output_%.%", ctx.name, ext);
            ok := write_entire_file(filename, s);
            if !ok {
              log_error("Error writing file to '%'", filename);
            } else {
              log("Transpiled Jai to %", filename);
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
  log("Converting % Shader: %", ctx.type, node.header.name);
  
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

write_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if ctx.language == {
    case .GLSL;  return write_glsl_shader_code (ctx, node);
    case .HLSL;  return write_hlsl_shader_code (ctx, node);
    case .METAL; return write_metal_shader_code(ctx, node);
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
  if cast(u8)op == {
    case #char "="; return "=";
    case #char "<"; return "<";
    case #char "?"; return "?";
    case #char ">"; return ">";
    case #char "!"; return "!";
    case #char "+"; return "+";
    case #char "-"; return "-";
    case #char "*"; return "*";
    case #char "/"; return "/";
    case #char "%"; return "%";
    case #char "~"; return "~";
    case #char "."; return ".";
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
    
    //case ARRAY_SUBSCRIPT; return "[]";
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
}

node_is_fragment_shader :: (node: *Code_Procedure_Header) -> bool {
  for node.notes if it.text == "fragment_shader" return true;
  return false;
}

member_has_note :: (member: *Type_Info_Struct_Member, note: string) -> bool {
  for member.notes if it == note return true;
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
    };
}
