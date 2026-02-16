#import "Basic";
#import "Math";
#import "ShaderFuncs";
#import,file "../module.jai";

#load "vulkan_shaders.jai";

main :: () {}

on_dll_init :: () {
  _ = get_transpiled(.VULKAN_GLSL, bindless_nested_vertex_vk);
  _ = get_transpiled(.VULKAN_GLSL, bindless_texture_fragment_vk);
}
