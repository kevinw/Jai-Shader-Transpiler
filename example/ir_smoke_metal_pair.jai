#import "Basic";
#import "Math";
#import "ShaderFuncs";
#import,file "../module.jai";

#load "glsl_shaders.jai";

main :: () {}

on_dll_init :: () {
  _ = get_transpiled(.METAL, tiles_vertex_shader, tiles_fragment_shader);
}
