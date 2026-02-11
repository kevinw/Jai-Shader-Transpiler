#import "Basic";
#import "Math";
#import "ShaderFuncs";
#import,file "../module.jai";

#load "glsl_shaders.jai";
#load "vulkan_shaders.jai";
#load "array_shader_tests.jai";
#load "compute_shader_tests.jai";

main :: () {
  // Intentionally empty. This target is only for compile-time IR pipeline smoke checks.
}

on_dll_init :: () {
  // Metal graphics pair request.
  _ = get_transpiled(.METAL, tiles_vertex_shader, tiles_fragment_shader);

  // Vulkan GLSL requests, including nested pointer access coverage.
  _ = get_transpiled(.VULKAN_GLSL, compute_write_indices_vk);
  _ = get_transpiled(.VULKAN_GLSL, bindless_nested_vertex_vk);
}
