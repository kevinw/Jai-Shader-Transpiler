/*

#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
};

vertex VSOut vs_main(uint vid [[vertex_id]])
{
    float2 positions[3] = {
        float2( 0.0,  0.5),
        float2(-0.5, -0.5),
        float2( 0.5, -0.5)
    };

    VSOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    return out;
}

fragment float4 fs_main()
{
    return float4(1.0, 0.0, 0.0, 1.0); // red
}

*/
write_metal_compute_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "/* TODO: write_metal_compute_shader */";
}

write_metal_vertex_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "/* TODO: write_metal_vertex_shader */";
}

write_metal_fragment_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "/* TODO: write_metal_fragment_shader */";
}

write_metal_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "/* TODO: write_metal_shader_code */";
}

print_metal_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: Code_Procedure_Header) {
  append(sb, "/* TODO: print_metal_function: ", fn.name, " */");
}

print_metal_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_metal_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}

print_metal_expr :: (using ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  // TODO
  PP.print_expression(sb, node);
}
