#import "Basic";
#import "Math";
#import "File";
#import "Command_Line";
Process :: #import "Process";
using,except(NO) SDL :: #import "SDL";
Vulkan :: #import,file "/Users/kev/src/peel/modules/sgpu/modules/Vulkan_With_VMA/module.jai"(MEMORY_ALLOCATOR_DEBUG=false, USE_LOCAL_VULKAN_DYNAMIC_LIB=true);
using Vulkan;

#import,file "../module.jai";
#load "vulkan_shaders.jai";
#load "example_common.jai";

SDL_Vulkan_LoadLibrary :: (path: *u8) -> s32 #foreign SDL2;
SDL_Vulkan_UnloadLibrary :: () #foreign SDL2;
SDL_Vulkan_GetInstanceExtensions :: (window: *SDL_Window, pCount: *u32, pNames: **u8) -> SDL_bool #foreign SDL2;
SDL_Vulkan_CreateSurface :: (window: *SDL_Window, instance: VkInstance, pSurface: *VkSurfaceKHR) -> SDL_bool #foreign SDL2;

MOLTENVK_LOCAL_LIB :: "/Users/kev/src/peel/modules/sgpu/modules/Vulkan_With_VMA/libs/mac/libvulkan.1.4.335.dylib";

Vertex2 :: struct {
    pos: Vector2;
}

Fragment_Uniforms :: struct {
    u_resolution: Vector2;
    u_time: float32;
    _pad: float32;
}


fail :: (message: string, args: .. Any) {
    log_error(message, ..args);
    exit(1);
}

check_vk :: (result: VkResult, step: string) {
    if result != .SUCCESS {
        fail("% failed with VkResult=%", step, cast(s32) result);
    }
}

run_command_checked :: (description: string, args: [] string, timeout_ms := -1) {
    command := Process.get_quoted_command_string(args);
    result, output, error, timeout_reached := Process.run_command(..args, timeout_ms=timeout_ms);

    if timeout_reached fail("% timed out. Command: %", description, command);
    if result.type == .FAILED_TO_LAUNCH fail("% failed to launch. Command: %", description, command);
    if result.type != .EXITED || result.exit_code != 0 {
        if output.count != 0 log_error("%", output);
        if error.count != 0 log_error("%", error);
        fail("% failed with exit code %. Command: %", description, result.exit_code, command);
    }
}

write_shader_source :: (dir: string, basename: string, extension: string, source: string) -> string {
    path := tprint("%/%.%", dir, basename, extension);
    ok := write_entire_file(path, source);
    if !ok fail("Failed to write shader source file %", path);
    return path;
}

compile_glsl_to_spirv :: (source_path: string, stage: string) -> string {
    output_path := tprint("%.spv", source_path);
    run_command_checked(tprint("Compile %", source_path),
        .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", stage, source_path, "-o", output_path]);
    return output_path;
}

alloc_c_string :: (s: string) -> *u8 {
    p := cast(*u8) alloc(s.count + 1);
    memcpy(p, s.data, s.count);
    p[s.count] = 0;
    return p;
}

free_c_strings :: (arr: [] *u8) {
    for arr if it != null free(it);
}

find_memory_type :: (mem_props: *VkPhysicalDeviceMemoryProperties, type_bits: u32, required: VkMemoryPropertyFlags) -> s32 {
    for i: 0..mem_props.memoryTypeCount-1 {
        if (type_bits & (1 << i)) == 0 continue;
        if (mem_props.memoryTypes[i].propertyFlags & required) == required return cast(s32) i;
    }
    return -1;
}

create_buffer :: (device: VkDevice, mem_props: *VkPhysicalDeviceMemoryProperties, size: u64,
                  usage: VkBufferUsageFlags, memory_flags: VkMemoryPropertyFlags,
                  initial_data: *void = null) -> VkBuffer, VkDeviceMemory {
    buffer_info := VkBufferCreateInfo.{
        size = size,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    };

    buffer: VkBuffer;
    check_vk(vkCreateBuffer(device, *buffer_info, null, *buffer), "vkCreateBuffer");

    requirements: VkMemoryRequirements;
    vkGetBufferMemoryRequirements(device, buffer, *requirements);

    memory_type := find_memory_type(mem_props, requirements.memoryTypeBits,
        memory_flags);
    if memory_type < 0 fail("Could not find Vulkan memory type for buffer");

    alloc_info := VkMemoryAllocateInfo.{
        allocationSize = requirements.size,
        memoryTypeIndex = cast(u32) memory_type,
    };

    memory: VkDeviceMemory;
    check_vk(vkAllocateMemory(device, *alloc_info, null, *memory), "vkAllocateMemory");
    check_vk(vkBindBufferMemory(device, buffer, memory, 0), "vkBindBufferMemory");

    if initial_data != null {
        mapped: *void;
        check_vk(vkMapMemory(device, memory, 0, size, 0, *mapped), "vkMapMemory");
        memcpy(mapped, initial_data, cast(s64) size);
        vkUnmapMemory(device, memory);
    }

    return buffer, memory;
}

choose_surface_format :: (formats: [] VkSurfaceFormatKHR) -> VkSurfaceFormatKHR {
    for formats {
        if it.format == .B8G8R8A8_UNORM && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR return it;
    }
    return formats[0];
}

choose_present_mode :: (modes: [] VkPresentModeKHR) -> VkPresentModeKHR {
    for modes if it == .MAILBOX_KHR return it;
    return .FIFO_KHR;
}

main :: () {
    _ = get_transpiled(.VULKAN_GLSL, tiles_vertex_shader_vk);
    _ = get_transpiled(.VULKAN_GLSL, tiles_fragment_shader_vk);
    _ = get_transpiled(.VULKAN_GLSL, compute_write_indices_vk);

    args_ok, args, is_set := parse_arguments(struct { single_frame: bool; test_readback: bool; });
    single_frame := args_ok && is_set.single_frame;
    test_readback := args_ok && is_set.test_readback;
    max_frames: s64 = ifx single_frame then 1 else 0x7FFF_FFFF_FFFF_FFFF;

    _ := tiles_vertex_shader_vk(.{}, .{});
    _ = tiles_fragment_shader_vk(.{}, .{});
    _ = compute_write_indices_vk;

    output_dir :: ".build/vulkan_example";
    if !make_directory_if_it_does_not_exist(output_dir, recursive=true) {
        fail("Failed to create output directory %", output_dir);
    }

    vertex_glsl := write_shader_source(output_dir, "tiles_vertex_shader_vk", "vert.glsl", get_transpiled(.VULKAN_GLSL, tiles_vertex_shader_vk));
    fragment_glsl := write_shader_source(output_dir, "tiles_fragment_shader_vk", "frag.glsl", get_transpiled(.VULKAN_GLSL, tiles_fragment_shader_vk));
    compute_glsl := write_shader_source(output_dir, "compute_write_indices_vk", "comp.glsl", get_transpiled(.VULKAN_GLSL, compute_write_indices_vk));

    vertex_spv := compile_glsl_to_spirv(vertex_glsl, "vert");
    fragment_spv := compile_glsl_to_spirv(fragment_glsl, "frag");
    _ = compile_glsl_to_spirv(compute_glsl, "comp");

    if SDL_Init(SDL_INIT_VIDEO) != 0 fail("SDL_Init failed: %", to_string(SDL_GetError()));
    defer SDL_Quit();

    if SDL_Vulkan_LoadLibrary(null) != 0 {
        #if OS == .MACOS {
            if SDL_Vulkan_LoadLibrary(MOLTENVK_LOCAL_LIB.data) != 0 {
                fail("SDL_Vulkan_LoadLibrary failed: %", to_string(SDL_GetError()));
            }
        } else {
            fail("SDL_Vulkan_LoadLibrary failed: %", to_string(SDL_GetError()));
        }
    }
    defer SDL_Vulkan_UnloadLibrary();

    window := SDL_CreateWindow("Vulkan Transpiler Sample", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        1080, 720, .SDL_WINDOW_VULKAN);
    if !window fail("SDL_CreateWindow(VULKAN) failed: %", to_string(SDL_GetError()));
    defer SDL_DestroyWindow(window);

    ext_count: u32 = 0;
    if SDL_Vulkan_GetInstanceExtensions(window, *ext_count, null) == .SDL_FALSE {
        fail("SDL_Vulkan_GetInstanceExtensions(count) failed: %", to_string(SDL_GetError()));
    }

    extensions: [..] *u8;
    for i: 0..ext_count-1 array_add(*extensions, null);
    if SDL_Vulkan_GetInstanceExtensions(window, *ext_count, extensions.data) == .SDL_FALSE {
        fail("SDL_Vulkan_GetInstanceExtensions(names) failed: %", to_string(SDL_GetError()));
    }

    #if OS == .MACOS {
    portability_ext := alloc_c_string(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        array_add(*extensions, portability_ext);
        defer free(portability_ext);
    }

    app_name := alloc_c_string("Jai Shader Transpiler Vulkan Example");
    engine_name := alloc_c_string("Jai-To-Shader");
    defer {
        free(app_name);
        free(engine_name);
    }

    app_info := VkApplicationInfo.{
        pApplicationName = app_name,
        applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0),
        pEngineName = engine_name,
        engineVersion = VK_MAKE_API_VERSION(0, 0, 1, 0),
        apiVersion = VK_API_VERSION_1_2,
    };

    instance_info := VkInstanceCreateInfo.{
        pApplicationInfo = *app_info,
        enabledExtensionCount = cast(u32) extensions.count,
        ppEnabledExtensionNames = extensions.data,
    };
    #if OS == .MACOS {
        instance_info.flags = .ENUMERATE_PORTABILITY_BIT_KHR;
    }

    instance: VkInstance;
    check_vk(vkCreateInstance(*instance_info, null, *instance), "vkCreateInstance");
    defer vkDestroyInstance(instance, null);

    surface: VkSurfaceKHR;
    if SDL_Vulkan_CreateSurface(window, instance, *surface) == .SDL_FALSE {
        fail("SDL_Vulkan_CreateSurface failed: %", to_string(SDL_GetError()));
    }
    defer vkDestroySurfaceKHR(instance, surface, null);

    physical_count: u32 = 0;
    check_vk(vkEnumeratePhysicalDevices(instance, *physical_count, null), "vkEnumeratePhysicalDevices(count)");
    if physical_count == 0 fail("No Vulkan physical devices found");

    physical_devices: [..] VkPhysicalDevice;
    for i: 0..physical_count-1 array_add(*physical_devices, null);
    check_vk(vkEnumeratePhysicalDevices(instance, *physical_count, physical_devices.data), "vkEnumeratePhysicalDevices(list)");

    selected_physical: VkPhysicalDevice = null;
    graphics_queue_family: u32 = 0;

    for physical_devices {
        queue_family_count: u32 = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(it, *queue_family_count, null);
        queue_props: [..] VkQueueFamilyProperties;
        for q: 0..queue_family_count-1 array_add(*queue_props, .{});
        vkGetPhysicalDeviceQueueFamilyProperties(it, *queue_family_count, queue_props.data);

        for q: 0..queue_family_count-1 {
            supports_present: VkBool32 = VK_FALSE;
            check_vk(vkGetPhysicalDeviceSurfaceSupportKHR(it, q, surface, *supports_present), "vkGetPhysicalDeviceSurfaceSupportKHR");
            supports_graphics := (queue_props[q].queueFlags & .GRAPHICS_BIT) != 0;
            if supports_graphics && supports_present == VK_TRUE {
                selected_physical = it;
                graphics_queue_family = q;
                break;
            }
        }

        if selected_physical != null break;
    }

    if selected_physical == null fail("No Vulkan device with graphics+present support found");

    queue_priority: float = 1.0;
    queue_info := VkDeviceQueueCreateInfo.{
        queueFamilyIndex = graphics_queue_family,
        queueCount = 1,
        pQueuePriorities = *queue_priority,
    };

    swapchain_ext := alloc_c_string(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    defer free(swapchain_ext);
    device_extensions: [1] *u8;
    device_extensions[0] = swapchain_ext;

    device_info := VkDeviceCreateInfo.{
        queueCreateInfoCount = 1,
        pQueueCreateInfos = *queue_info,
        enabledExtensionCount = 1,
        ppEnabledExtensionNames = device_extensions.data,
    };

    device: VkDevice;
    check_vk(vkCreateDevice(selected_physical, *device_info, null, *device), "vkCreateDevice");
    defer vkDestroyDevice(device, null);

    queue: VkQueue;
    vkGetDeviceQueue(device, graphics_queue_family, 0, *queue);

    surface_caps: VkSurfaceCapabilitiesKHR;
    check_vk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(selected_physical, surface, *surface_caps), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");

    format_count: u32 = 0;
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(selected_physical, surface, *format_count, null), "vkGetPhysicalDeviceSurfaceFormatsKHR(count)");
    if format_count == 0 fail("No Vulkan surface formats");
    surface_formats: [..] VkSurfaceFormatKHR;
    for i: 0..format_count-1 array_add(*surface_formats, .{});
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(selected_physical, surface, *format_count, surface_formats.data), "vkGetPhysicalDeviceSurfaceFormatsKHR(list)");
    surface_format := choose_surface_format(surface_formats);

    present_mode_count: u32 = 0;
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(selected_physical, surface, *present_mode_count, null), "vkGetPhysicalDeviceSurfacePresentModesKHR(count)");
    present_modes: [..] VkPresentModeKHR;
    for i: 0..present_mode_count-1 array_add(*present_modes, .IMMEDIATE_KHR);
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(selected_physical, surface, *present_mode_count, present_modes.data), "vkGetPhysicalDeviceSurfacePresentModesKHR(list)");
    present_mode := choose_present_mode(present_modes);

    extent := surface_caps.currentExtent;
    if extent.width == 0xFFFF_FFFF {
        extent.width = 1080;
        extent.height = 720;
    }

    image_count := surface_caps.minImageCount + 1;
    if surface_caps.maxImageCount != 0 && image_count > surface_caps.maxImageCount {
        image_count = surface_caps.maxImageCount;
    }

    swapchain_usage := VkImageUsageFlags.COLOR_ATTACHMENT_BIT;
    if test_readback {
        if (surface_caps.supportedUsageFlags & .TRANSFER_SRC_BIT) != 0 {
            swapchain_usage |= .TRANSFER_SRC_BIT;
        } else {
            log("Vulkan readback requested but swapchain doesn't support TRANSFER_SRC usage; disabling readback.");
            test_readback = false;
        }
    }

    swapchain_info := VkSwapchainCreateInfoKHR.{
        surface = surface,
        minImageCount = image_count,
        imageFormat = surface_format.format,
        imageColorSpace = surface_format.colorSpace,
        imageExtent = extent,
        imageArrayLayers = 1,
        imageUsage = swapchain_usage,
        imageSharingMode = .EXCLUSIVE,
        preTransform = surface_caps.currentTransform,
        compositeAlpha = .OPAQUE_BIT_KHR,
        presentMode = present_mode,
        clipped = VK_TRUE,
    };

    swapchain: VkSwapchainKHR;
    check_vk(vkCreateSwapchainKHR(device, *swapchain_info, null, *swapchain), "vkCreateSwapchainKHR");
    defer vkDestroySwapchainKHR(device, swapchain, null);

    swap_img_count: u32 = 0;
    check_vk(vkGetSwapchainImagesKHR(device, swapchain, *swap_img_count, null), "vkGetSwapchainImagesKHR(count)");
    swap_images: [..] VkImage;
    for i: 0..swap_img_count-1 array_add(*swap_images, null);
    check_vk(vkGetSwapchainImagesKHR(device, swapchain, *swap_img_count, swap_images.data), "vkGetSwapchainImagesKHR(list)");

    image_views: [..] VkImageView;
    for swap_images {
        view_info := VkImageViewCreateInfo.{
            image = it,
            viewType = ._2D,
            format = surface_format.format,
            subresourceRange = .{
                aspectMask = .COLOR_BIT,
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        };
        view: VkImageView;
        check_vk(vkCreateImageView(device, *view_info, null, *view), "vkCreateImageView");
        array_add(*image_views, view);
    }
    defer for image_views vkDestroyImageView(device, it, null);

    vertex_spv_bytes, ok := read_entire_file(vertex_spv);
    if !ok fail("Failed reading %", vertex_spv);
    fragment_spv_bytes, ok2 := read_entire_file(fragment_spv);
    if !ok2 fail("Failed reading %", fragment_spv);

    vert_module_info := VkShaderModuleCreateInfo.{
        codeSize = cast(u64) vertex_spv_bytes.count,
        pCode = cast(*u32) vertex_spv_bytes.data,
    };
    frag_module_info := VkShaderModuleCreateInfo.{
        codeSize = cast(u64) fragment_spv_bytes.count,
        pCode = cast(*u32) fragment_spv_bytes.data,
    };

    vert_module: VkShaderModule;
    frag_module: VkShaderModule;
    check_vk(vkCreateShaderModule(device, *vert_module_info, null, *vert_module), "vkCreateShaderModule(vertex)");
    check_vk(vkCreateShaderModule(device, *frag_module_info, null, *frag_module), "vkCreateShaderModule(fragment)");
    defer {
        vkDestroyShaderModule(device, vert_module, null);
        vkDestroyShaderModule(device, frag_module, null);
    }

    descriptor_binding := VkDescriptorSetLayoutBinding.{
        binding = 0,
        descriptorType = .UNIFORM_BUFFER,
        descriptorCount = 1,
        stageFlags = .FRAGMENT_BIT,
    };
    descriptor_layout_info := VkDescriptorSetLayoutCreateInfo.{
        bindingCount = 1,
        pBindings = *descriptor_binding,
    };

    descriptor_set_layout: VkDescriptorSetLayout;
    check_vk(vkCreateDescriptorSetLayout(device, *descriptor_layout_info, null, *descriptor_set_layout), "vkCreateDescriptorSetLayout");
    defer vkDestroyDescriptorSetLayout(device, descriptor_set_layout, null);

    pipeline_layout_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *descriptor_set_layout,
    };

    pipeline_layout: VkPipelineLayout;
    check_vk(vkCreatePipelineLayout(device, *pipeline_layout_info, null, *pipeline_layout), "vkCreatePipelineLayout");
    defer vkDestroyPipelineLayout(device, pipeline_layout, null);

    attachment_desc := VkAttachmentDescription.{
        format = surface_format.format,
        samples = ._1_BIT,
        loadOp = .CLEAR,
        storeOp = .STORE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .PRESENT_SRC_KHR,
    };
    attachment_ref := VkAttachmentReference.{
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL,
    };
    subpass := VkSubpassDescription.{
        pipelineBindPoint = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments = *attachment_ref,
    };
    subpass_dependency := VkSubpassDependency.{
        srcSubpass = VK_SUBPASS_EXTERNAL,
        dstSubpass = 0,
        srcStageMask = .COLOR_ATTACHMENT_OUTPUT_BIT,
        dstStageMask = .COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask = .COLOR_ATTACHMENT_WRITE_BIT,
    };
    renderpass_info := VkRenderPassCreateInfo.{
        attachmentCount = 1,
        pAttachments = *attachment_desc,
        subpassCount = 1,
        pSubpasses = *subpass,
        dependencyCount = 1,
        pDependencies = *subpass_dependency,
    };

    render_pass: VkRenderPass;
    check_vk(vkCreateRenderPass(device, *renderpass_info, null, *render_pass), "vkCreateRenderPass");
    defer vkDestroyRenderPass(device, render_pass, null);

    framebuffers: [..] VkFramebuffer;
    for image_views {
        framebuffer_info := VkFramebufferCreateInfo.{
            renderPass = render_pass,
            attachmentCount = 1,
            pAttachments = *it,
            width = extent.width,
            height = extent.height,
            layers = 1,
        };
        framebuffer: VkFramebuffer;
        check_vk(vkCreateFramebuffer(device, *framebuffer_info, null, *framebuffer), "vkCreateFramebuffer");
        array_add(*framebuffers, framebuffer);
    }
    defer for framebuffers vkDestroyFramebuffer(device, it, null);

    entry_name := alloc_c_string("main");
    defer free(entry_name);

    stages := VkPipelineShaderStageCreateInfo.[
        .{ stage = .VERTEX_BIT, module = vert_module, pName = entry_name },
        .{ stage = .FRAGMENT_BIT, module = frag_module, pName = entry_name },
    ];

    vertex_binding := VkVertexInputBindingDescription.{
        binding = 0,
        stride = size_of(Vertex2),
        inputRate = .VERTEX,
    };
    vertex_attr := VkVertexInputAttributeDescription.{
        location = 0,
        binding = 0,
        format = .R32G32_SFLOAT,
        offset = 0,
    };
    vertex_input_state := VkPipelineVertexInputStateCreateInfo.{
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = *vertex_binding,
        vertexAttributeDescriptionCount = 1,
        pVertexAttributeDescriptions = *vertex_attr,
    };

    input_assembly_state := VkPipelineInputAssemblyStateCreateInfo.{
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = VK_FALSE,
    };

    viewport := VkViewport.{ x = 0, y = 0, width = xx extent.width, height = xx extent.height, minDepth = 0, maxDepth = 1 };
    scissor := VkRect2D.{ extent = extent };
    viewport_state := VkPipelineViewportStateCreateInfo.{
        viewportCount = 1,
        pViewports = *viewport,
        scissorCount = 1,
        pScissors = *scissor,
    };

    rasterization_state := VkPipelineRasterizationStateCreateInfo.{
        polygonMode = .FILL,
        cullMode = .NONE,
        frontFace = .COUNTER_CLOCKWISE,
        lineWidth = 1,
    };

    multisample_state := VkPipelineMultisampleStateCreateInfo.{
        rasterizationSamples = ._1_BIT,
    };

    color_blend_attachment := VkPipelineColorBlendAttachmentState.{
        blendEnable = VK_FALSE,
        colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
    };
    color_blend_state := VkPipelineColorBlendStateCreateInfo.{
        attachmentCount = 1,
        pAttachments = *color_blend_attachment,
    };

    pipeline_info := VkGraphicsPipelineCreateInfo.{
        stageCount = stages.count,
        pStages = stages.data,
        pVertexInputState = *vertex_input_state,
        pInputAssemblyState = *input_assembly_state,
        pViewportState = *viewport_state,
        pRasterizationState = *rasterization_state,
        pMultisampleState = *multisample_state,
        pColorBlendState = *color_blend_state,
        layout = pipeline_layout,
        renderPass = render_pass,
        subpass = 0,
    };

    pipeline: VkPipeline;
    check_vk(vkCreateGraphicsPipelines(device, null, 1, *pipeline_info, null, *pipeline), "vkCreateGraphicsPipelines");
    defer vkDestroyPipeline(device, pipeline, null);

    mem_props: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(selected_physical, *mem_props);

    verts := Vertex2.[
        .{ .{-1, -1} },
        .{ .{ 1, -1} },
        .{ .{ 1,  1} },
        .{ .{-1,  1} },
    ];
    indices := u32.[0, 1, 2, 2, 3, 0];

    vertex_buffer, vertex_memory := create_buffer(device, *mem_props,
        verts.count * size_of(Vertex2), .VERTEX_BUFFER_BIT,
        .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *verts);
    defer {
        vkDestroyBuffer(device, vertex_buffer, null);
        vkFreeMemory(device, vertex_memory, null);
    }

    index_buffer, index_memory := create_buffer(device, *mem_props,
        indices.count * size_of(u32), .INDEX_BUFFER_BIT,
        .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *indices);
    defer {
        vkDestroyBuffer(device, index_buffer, null);
        vkFreeMemory(device, index_memory, null);
    }

    uniforms := Fragment_Uniforms.{
        u_resolution = .{ xx extent.width, xx extent.height },
        u_time = 0.0,
    };

    uniform_buffer, uniform_memory := create_buffer(device, *mem_props,
        size_of(Fragment_Uniforms), .UNIFORM_BUFFER_BIT,
        .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *uniforms);
    defer {
        vkDestroyBuffer(device, uniform_buffer, null);
        vkFreeMemory(device, uniform_memory, null);
    }

    readback_num_bytes: u64 = cast(u64) extent.width * extent.height * 4;
    readback_buffer: VkBuffer = null;
    readback_memory: VkDeviceMemory = null;
    if test_readback {
        readback_buffer, readback_memory = create_buffer(device, *mem_props,
            readback_num_bytes, .TRANSFER_DST_BIT,
            .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
    }
    defer if readback_buffer != null {
        vkDestroyBuffer(device, readback_buffer, null);
        vkFreeMemory(device, readback_memory, null);
    };

    pool_size := VkDescriptorPoolSize.{
        type = .UNIFORM_BUFFER,
        descriptorCount = 1,
    };
    descriptor_pool_info := VkDescriptorPoolCreateInfo.{
        maxSets = 1,
        poolSizeCount = 1,
        pPoolSizes = *pool_size,
    };
    descriptor_pool: VkDescriptorPool;
    check_vk(vkCreateDescriptorPool(device, *descriptor_pool_info, null, *descriptor_pool), "vkCreateDescriptorPool");
    defer vkDestroyDescriptorPool(device, descriptor_pool, null);

    descriptor_alloc_info := VkDescriptorSetAllocateInfo.{
        descriptorPool = descriptor_pool,
        descriptorSetCount = 1,
        pSetLayouts = *descriptor_set_layout,
    };
    descriptor_set: VkDescriptorSet;
    check_vk(vkAllocateDescriptorSets(device, *descriptor_alloc_info, *descriptor_set), "vkAllocateDescriptorSets");

    buffer_info := VkDescriptorBufferInfo.{
        buffer = uniform_buffer,
        offset = 0,
        range = size_of(Fragment_Uniforms),
    };
    write := VkWriteDescriptorSet.{
        dstSet = descriptor_set,
        dstBinding = 0,
        descriptorCount = 1,
        descriptorType = .UNIFORM_BUFFER,
        pBufferInfo = *buffer_info,
    };
    vkUpdateDescriptorSets(device, 1, *write, 0, null);

    command_pool_info := VkCommandPoolCreateInfo.{
        flags = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = graphics_queue_family,
    };
    command_pool: VkCommandPool;
    check_vk(vkCreateCommandPool(device, *command_pool_info, null, *command_pool), "vkCreateCommandPool");
    defer vkDestroyCommandPool(device, command_pool, null);

    command_alloc_info := VkCommandBufferAllocateInfo.{
        commandPool = command_pool,
        level = .PRIMARY,
        commandBufferCount = 1,
    };
    command_buffer: VkCommandBuffer;
    check_vk(vkAllocateCommandBuffers(device, *command_alloc_info, *command_buffer), "vkAllocateCommandBuffers");

    semaphore_info := VkSemaphoreCreateInfo.{};
    image_available: VkSemaphore;
    render_finished: VkSemaphore;
    check_vk(vkCreateSemaphore(device, *semaphore_info, null, *image_available), "vkCreateSemaphore(image_available)");
    check_vk(vkCreateSemaphore(device, *semaphore_info, null, *render_finished), "vkCreateSemaphore(render_finished)");
    defer {
        vkDestroySemaphore(device, image_available, null);
        vkDestroySemaphore(device, render_finished, null);
    }

    fence_info := VkFenceCreateInfo.{ flags = .SIGNALED_BIT };
    in_flight: VkFence;
    check_vk(vkCreateFence(device, *fence_info, null, *in_flight), "vkCreateFence");
    defer vkDestroyFence(device, in_flight, null);

    frame_index: s64 = 0;
    quit := false;
    while !quit && frame_index < max_frames {
        event: SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == SDL_QUIT {
                quit = true;
            }
        }

        uniforms.u_time = xx frame_index * 0.016;
        mapped_uniforms: *void;
        check_vk(vkMapMemory(device, uniform_memory, 0, size_of(Fragment_Uniforms), 0, *mapped_uniforms), "vkMapMemory(uniform)");
        memcpy(mapped_uniforms, *uniforms, size_of(Fragment_Uniforms));
        vkUnmapMemory(device, uniform_memory);

        check_vk(vkWaitForFences(device, 1, *in_flight, VK_TRUE, U64_MAX), "vkWaitForFences");
        check_vk(vkResetFences(device, 1, *in_flight), "vkResetFences");
        check_vk(vkResetCommandBuffer(command_buffer, 0), "vkResetCommandBuffer");

        image_index: u32;
        check_vk(vkAcquireNextImageKHR(device, swapchain, U64_MAX, image_available, null, *image_index), "vkAcquireNextImageKHR");

        begin_info := VkCommandBufferBeginInfo.{};
        check_vk(vkBeginCommandBuffer(command_buffer, *begin_info), "vkBeginCommandBuffer");

        clear_color := VkClearValue.{ color._float32 = .[0.0, 0.0, 0.0, 1.0] };
        render_pass_info := VkRenderPassBeginInfo.{
            renderPass = render_pass,
            framebuffer = framebuffers[image_index],
            renderArea = .{ extent = extent },
            clearValueCount = 1,
            pClearValues = *clear_color,
        };

        vkCmdBeginRenderPass(command_buffer, *render_pass_info, .INLINE);
        vkCmdBindPipeline(command_buffer, .GRAPHICS, pipeline);
        vkCmdBindDescriptorSets(command_buffer, .GRAPHICS, pipeline_layout, 0, 1, *descriptor_set, 0, null);

        vb_offset: VkDeviceSize = 0;
        vkCmdBindVertexBuffers(command_buffer, 0, 1, *vertex_buffer, *vb_offset);
        vkCmdBindIndexBuffer(command_buffer, index_buffer, 0, .UINT32);
        vkCmdDrawIndexed(command_buffer, indices.count, 1, 0, 0, 0);
        vkCmdEndRenderPass(command_buffer);

        if test_readback {
            to_transfer := VkImageMemoryBarrier.{
                srcAccessMask = .COLOR_ATTACHMENT_WRITE_BIT,
                dstAccessMask = .TRANSFER_READ_BIT,
                oldLayout = .PRESENT_SRC_KHR,
                newLayout = .TRANSFER_SRC_OPTIMAL,
                srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                image = swap_images[image_index],
                subresourceRange = .{
                    aspectMask = .COLOR_BIT,
                    baseMipLevel = 0,
                    levelCount = 1,
                    baseArrayLayer = 0,
                    layerCount = 1,
                },
            };
            vkCmdPipelineBarrier(command_buffer,
                .COLOR_ATTACHMENT_OUTPUT_BIT, .TRANSFER_BIT, 0,
                0, null, 0, null, 1, *to_transfer);

            copy_region := VkBufferImageCopy.{
                bufferOffset = 0,
                imageSubresource = .{
                    aspectMask = .COLOR_BIT,
                    mipLevel = 0,
                    baseArrayLayer = 0,
                    layerCount = 1,
                },
                imageExtent = .{ extent.width, extent.height, 1 },
            };
            vkCmdCopyImageToBuffer(command_buffer, swap_images[image_index], .TRANSFER_SRC_OPTIMAL, readback_buffer, 1, *copy_region);

            to_present := VkImageMemoryBarrier.{
                srcAccessMask = .TRANSFER_READ_BIT,
                dstAccessMask = xx 0,
                oldLayout = .TRANSFER_SRC_OPTIMAL,
                newLayout = .PRESENT_SRC_KHR,
                srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                image = swap_images[image_index],
                subresourceRange = .{
                    aspectMask = .COLOR_BIT,
                    baseMipLevel = 0,
                    levelCount = 1,
                    baseArrayLayer = 0,
                    layerCount = 1,
                },
            };
            vkCmdPipelineBarrier(command_buffer,
                .TRANSFER_BIT, .BOTTOM_OF_PIPE_BIT, 0,
                0, null, 0, null, 1, *to_present);
        }

        check_vk(vkEndCommandBuffer(command_buffer), "vkEndCommandBuffer");

        wait_stage := VkPipelineStageFlags.[.COLOR_ATTACHMENT_OUTPUT_BIT];
        submit_info := VkSubmitInfo.{
            waitSemaphoreCount = 1,
            pWaitSemaphores = *image_available,
            pWaitDstStageMask = wait_stage.data,
            commandBufferCount = 1,
            pCommandBuffers = *command_buffer,
            signalSemaphoreCount = 1,
            pSignalSemaphores = *render_finished,
        };

        check_vk(vkQueueSubmit(queue, 1, *submit_info, in_flight), "vkQueueSubmit");

        present_info := VkPresentInfoKHR.{
            waitSemaphoreCount = 1,
            pWaitSemaphores = *render_finished,
            swapchainCount = 1,
            pSwapchains = *swapchain,
            pImageIndices = *image_index,
        };
        check_vk(vkQueuePresentKHR(queue, *present_info), "vkQueuePresentKHR");

        if test_readback {
            check_vk(vkWaitForFences(device, 1, *in_flight, VK_TRUE, U64_MAX), "vkWaitForFences(readback)");

            mapped_readback: *void;
            check_vk(vkMapMemory(device, readback_memory, 0, readback_num_bytes, 0, *mapped_readback), "vkMapMemory(readback)");
            readback_pixels: [] u8;
            readback_pixels.data = cast(*u8) mapped_readback;
            readback_pixels.count = cast(s64) readback_num_bytes;
            ok := validate_readback_samples("vulkan", readback_pixels, cast(s32) extent.width, cast(s32) extent.height, cast(s64) extent.width * 4, is_bgra=true);
            vkUnmapMemory(device, readback_memory);
            if !ok exit(1);
            test_readback = false;
        }

        frame_index += 1;
    }

    check_vk(vkDeviceWaitIdle(device), "vkDeviceWaitIdle");
    log("Vulkan sample succeeded: transpiled shaders compiled and rendered % frame(s).", frame_index);
}
