#import "Basic";
#import "Math";
using,except(NO) SDL :: #import "SDL";
#import "Metal";
#import "Command_Line";
#import "Objective_C";

#import,dir "..";
#load "glsl_shaders.jai";
#load "array_shader_tests.jai";

Fragment_Shader_Uniforms :: struct {
    u_resolution: Vector2;
    u_time: float32;
    _pad: float32;
}

log_nserror :: (label: string, error: *NSError) -> bool {
    if error == null return false;
    
    log("logging error %", error);

    ns_description := NSError.localizedDescription(error);
    if ns_description {
        log_error("%: %", label, to_string(NSString.UTF8String(ns_description)));
    } else {
        log_error("%: (NSError with no description)", label);
    }
    return true;
}

metal_example_with_window :: () -> (success: bool) {
    args_ok, args, is_set := parse_arguments(struct { singleframe: bool; });
    singleframe := args_ok && is_set.singleframe;
    max_frames := ifx singleframe then 1 else 0x7FFF_FFFF_FFFF_FFFF;
  
    init_objective_c();
    init_metal();

    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
    SDL_Init(SDL_INIT_VIDEO);
    defer SDL_Quit();

    window := SDL_CreateWindow("FancyTiles (Metal)", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1080, 720, SDL_WINDOW_ALLOW_HIGHDPI);
    if !window {
        log_error("Could not create window: %", to_string(SDL_GetError()));
        return false;
    }
    defer SDL_DestroyWindow(window);

    renderer := SDL_CreateRenderer(window, -1, .PRESENTVSYNC);
    if !renderer {
        log_error("Could not create renderer: %", to_string(SDL_GetError()));
        return false;
    }
    defer SDL_DestroyRenderer(renderer);

    swapchain := cast(*CAMetalLayer) SDL_RenderGetMetalLayer(renderer);
    if !swapchain {
        log_error("Could not get CAMetalLayer from SDL renderer");
        return false;
    }

    device := CAMetalLayer.device(swapchain);
    if !device {
        log_error("Could not get Metal device from CAMetalLayer");
        return false;
    }

    pixel_format := CAMetalLayer.pixelFormat(swapchain);
    if pixel_format == .MTLPixelFormatInvalid {
        pixel_format = .MTLPixelFormatBGRA8Unorm;
        CAMetalLayer.setPixelFormat(swapchain, pixel_format);
    }

    queue := MTLDevice.newCommandQueue(device);
    if !queue {
        log_error("Failed to create Metal command queue");
        return false;
    }
    defer release(queue);

    error: *NSError = null;
    compile_options := objc_init(objc_alloc(MTLCompileOptions));
    defer release(compile_options);

    // Force array support test shaders to typecheck and generate.
    _ := array_support_vertex_shader(.{}, .{});
    _ = array_support_fragment_shader(.{}, .{});
    _ = array_support_vertex_shader_string;
    _ = array_support_fragment_shader_string;
    _ = array_support_vertex_shader_metal_string;
    _ = array_support_fragment_shader_metal_string;

    lib_vertex := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(tiles_vertex_shader_metal_string), compile_options, *error);
    if log_nserror("Failed to compile vertex shader library", error) || !lib_vertex {
        if !lib_vertex && error == null log_error("Failed to compile vertex shader library");
        return false;
    }
    defer release(lib_vertex);

    error = null;
    lib_fragment := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(tiles_fragment_shader_metal_string), compile_options, *error);
    if log_nserror("Failed to compile fragment shader library", error) || !lib_fragment {
        if !lib_fragment && error == null log_error("Failed to compile fragment shader library");
        return false;
    }
    defer release(lib_fragment);

    fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_vertex, NSString.getTempString("VertexMain"));
    if !fn_vertex {
        log_error("Failed to find vertex entry point 'main'");
        return false;
    }
    defer release(fn_vertex);

    fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_fragment, NSString.getTempString("FragmentMain"));
    if !fn_fragment {
        log_error("Failed to find fragment entry point 'main'");
        return false;
    }
    defer release(fn_fragment);

    vertex_desc := MTLVertexDescriptor.vertexDescriptor();
    defer release(vertex_desc);
    attr0 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.attributes(vertex_desc), 0);
    MTLVertexAttributeDescriptor.setFormat(attr0, .MTLVertexFormatFloat2);
    MTLVertexAttributeDescriptor.setOffset(attr0, 0);
    MTLVertexAttributeDescriptor.setBufferIndex(attr0, 0);
    layout0 := MTLVertexBufferLayoutDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.layouts(vertex_desc), 0);
    MTLVertexBufferLayoutDescriptor.setStride(layout0, size_of(Vector2));
    MTLVertexBufferLayoutDescriptor.setStepFunction(layout0, .MTLVertexStepFunctionPerVertex);
    MTLVertexBufferLayoutDescriptor.setStepRate(layout0, 1);

    pipeline_desc := objc_init(objc_alloc(MTLRenderPipelineDescriptor));
    defer release(pipeline_desc);
    MTLRenderPipelineDescriptor.setVertexFunction(pipeline_desc, xx fn_vertex);
    MTLRenderPipelineDescriptor.setFragmentFunction(pipeline_desc, xx fn_fragment);
    MTLRenderPipelineDescriptor.setVertexDescriptor(pipeline_desc, vertex_desc);
    color_attachment_desc := MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPipelineDescriptor.colorAttachments(pipeline_desc), 0);
    MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_desc, pixel_format);

    error = null;
    pipeline := MTLDevice.newRenderPipelineStateWithDescriptor_error(device, pipeline_desc, *error);
    if !pipeline || log_nserror("Failed to create Metal render pipeline", error) {
        if !pipeline && error == null log_error("Failed to create Metal render pipeline");
        return false;
    }
    defer release(pipeline);

    fs_triangle := Vector2.[
        Vector2.{ -1, -1 },
        Vector2.{  1, -1 },
        Vector2.{  1,  1 },
        Vector2.{ -1, -1 },
        Vector2.{  1,  1 },
        Vector2.{ -1,  1 },
    ];
    vertex_buffer := MTLDevice.newBufferWithBytes_length_options(device, *fs_triangle, fs_triangle.count * size_of(Vector2), .MTLResourceStorageModeShared);
    if !vertex_buffer {
        log_error("Failed to create Metal vertex buffer");
        return false;
    }
    defer release(vertex_buffer);

    quit := false;
    clear_color := MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    start := current_time_consensus();
    end := start;
    time_value: float32;
    frame_index := 0;
    while !quit && frame_index < max_frames {
        dt := to_float64_seconds(end - start);
        start = current_time_consensus();
        time_value += xx dt;

        event: SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == {
                case SDL_QUIT; quit = true;
                case SDL_KEYUP;
                    if event.key.keysym.sym == SDLK_ESCAPE quit = true;
            }
        }

        pool := objc_init(objc_alloc(NSAutoreleasePool));
        defer NSAutoreleasePool.drain(pool);

        drawable := CAMetalLayer.nextDrawable(swapchain);
        if !drawable {
            continue;
        }

        drawable_size := CAMetalLayer.drawableSize(swapchain);
        uniforms := Fragment_Shader_Uniforms.{
            u_resolution = .{ xx drawable_size.width, xx drawable_size.height },
            u_time = time_value,
        };
        dummy_uniform: u8 = 0;

        pass := MTLRenderPassDescriptor.renderPassDescriptor();
        color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
        MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, clear_color);
        MTLRenderPassAttachmentDescriptor.setLoadAction(color_attachment, .MTLLoadActionClear);
        MTLRenderPassAttachmentDescriptor.setStoreAction(color_attachment, .MTLStoreActionStore);
        MTLRenderPassAttachmentDescriptor.setTexture(color_attachment, CAMetalDrawable.texture(drawable));

        command_buffer := MTLCommandQueue.commandBuffer(queue);
        encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
        MTLRenderCommandEncoder.setRenderPipelineState(encoder, xx pipeline);
        MTLRenderCommandEncoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, 0);
        MTLRenderCommandEncoder.setVertexBytes_length_atIndex(encoder, *dummy_uniform, 1, 0);
        MTLRenderCommandEncoder.setFragmentBytes_length_atIndex(encoder, *uniforms, size_of(Fragment_Shader_Uniforms), 0);
        MTLRenderCommandEncoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, 6);
        MTLRenderCommandEncoder.endEncoding(encoder);

        MTLCommandBuffer.presentDrawable(command_buffer, xx drawable);
        MTLCommandBuffer.commit(command_buffer);
        end = current_time_consensus();
        
        frame_index += 1;
    }
    
    return true;
}

main :: () {
  if !metal_example_with_window() {
      exit(1);
  }
}
