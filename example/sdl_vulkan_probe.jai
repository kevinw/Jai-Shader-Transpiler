#import "Basic";
using,except(NO) SDL :: #import "SDL";

// Missing from current SDL Jai bindings; declared locally for probing.
SDL_Vulkan_LoadLibrary :: (path: *u8) -> s32 #foreign SDL2;
SDL_Vulkan_UnloadLibrary :: () #foreign SDL2;
SDL_Vulkan_GetVkGetInstanceProcAddr :: () -> *void #foreign SDL2;
SDL_Vulkan_GetInstanceExtensions :: (window: *SDL_Window, pCount: *u32, pNames: **u8) -> SDL_bool #foreign SDL2;

MOLTENVK_LOCAL_LIB :: "/Users/kev/src/peel/modules/sgpu/modules/Vulkan_With_VMA/libs/mac/libvulkan.1.4.335.dylib";

main :: () {
    if SDL_Init(SDL_INIT_VIDEO) != 0 {
        log_error("SDL_Init failed: %", to_string(SDL_GetError()));
        exit(1);
    }
    defer SDL_Quit();

    if SDL_Vulkan_LoadLibrary(null) != 0 {
        log("SDL_Vulkan_LoadLibrary(default) failed: %", to_string(SDL_GetError()));
        if SDL_Vulkan_LoadLibrary(MOLTENVK_LOCAL_LIB.data) != 0 {
            log_error("SDL_Vulkan_LoadLibrary(fallback='%') failed: %", MOLTENVK_LOCAL_LIB, to_string(SDL_GetError()));
            exit(1);
        }
        log("Loaded Vulkan loader via fallback path: %", MOLTENVK_LOCAL_LIB);
    }
    defer SDL_Vulkan_UnloadLibrary();

    window := SDL_CreateWindow("SDL Vulkan Probe",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        64, 64, .SDL_WINDOW_VULKAN | .SDL_WINDOW_HIDDEN);
    if !window {
        log_error("SDL_CreateWindow(VULKAN) failed: %", to_string(SDL_GetError()));
        exit(1);
    }
    defer SDL_DestroyWindow(window);

    proc := SDL_Vulkan_GetVkGetInstanceProcAddr();
    if !proc {
        log_error("SDL_Vulkan_GetVkGetInstanceProcAddr returned null.");
        exit(1);
    }

    ext_count: u32 = 0;
    ok := SDL_Vulkan_GetInstanceExtensions(window, *ext_count, null);
    if ok == .SDL_FALSE || ext_count == 0 {
        log_error("SDL_Vulkan_GetInstanceExtensions(count) failed: %", to_string(SDL_GetError()));
        exit(1);
    }

    ext_names: [..] *u8;
    ext_names.count = ext_count;
    ext_names.data = alloc(ext_count * size_of(*u8));
    if ext_names.data == null {
        log_error("Failed to allocate extension name array.");
        exit(1);
    }
    defer free(ext_names.data);

    ok = SDL_Vulkan_GetInstanceExtensions(window, *ext_count, ext_names.data);
    if ok == .SDL_FALSE {
        log_error("SDL_Vulkan_GetInstanceExtensions(names) failed: %", to_string(SDL_GetError()));
        exit(1);
    }

    log("SDL Vulkan probe succeeded. Required instance extensions (%):", ext_count);
    for i: 0..ext_count-1 {
        log("  %", to_string(ext_names[i]));
    }
}
