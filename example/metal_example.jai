#import "Basic";
#import "Math";
#import "Metal";
#import "Command_Line";
#import "Objective_C";
using,except(NO) SDL :: #import "SDL";
Debug :: #import "Debug";

#import,dir "..";
#load "glsl_shaders.jai";
#load "array_shader_tests.jai";
#load "compute_shader_tests.jai";

Fragment_Shader_Uniforms :: struct {
    u_resolution: Vector2;
    u_time: float32;
    _pad: float32;
}

VERTEX_UNIFORM_BUFFER_INDEX    :: 0;
VERTEX_ATTRIBUTE_BUFFER_INDEX  :: 1;
FRAGMENT_UNIFORM_BUFFER_INDEX  :: 0;

run_compute_sanity_check :: (device: *MTLDevice, queue: *MTLCommandQueue, compile_options: *MTLCompileOptions) -> bool {
    _ = compute_write_indices;
    _ = compute_write_indices_metal_string;

    error: *NSError = null;
    lib_compute := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(compute_write_indices_metal_string), compile_options, *error);
    if log_nserror("Failed to compile compute shader library", error) || !lib_compute {
        if !lib_compute && error == null log_error("Failed to compile compute shader library");
        return false;
    }
    defer release(lib_compute);

    fn_compute := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_compute, NSString.getTempString("ComputeMain"));
    if !fn_compute {
        log_error("Failed to find compute entry point 'ComputeMain'");
        return false;
    }
    defer release(fn_compute);

    error = null;
    pipeline_compute := MTLDevice.newComputePipelineStateWithFunction_error(device, xx fn_compute, *error);
    if log_nserror("Failed to create compute pipeline", error) || !pipeline_compute {
        if !pipeline_compute && error == null log_error("Failed to create compute pipeline");
        return false;
    }
    defer release(pipeline_compute);

    ELEMENT_COUNT :: 64;
    output_buffer_size := cast(NSUInteger) (ELEMENT_COUNT * size_of(u32));
    out_buffer := MTLDevice.newBufferWithLength_options(device, output_buffer_size, .MTLResourceStorageModeShared);
    if !out_buffer {
        log_error("Failed to create compute output buffer");
        return false;
    }
    defer release(out_buffer);

    out_data := cast(*u32) MTLBuffer.contents(out_buffer);
    if !out_data {
        log_error("Compute output buffer had null contents");
        return false;
    }
    for i: 0..ELEMENT_COUNT-1 out_data[i] = 0xFFFF_FFFF;

    command_buffer := MTLCommandQueue.commandBuffer(queue);
    if !command_buffer {
        log_error("Failed to create compute command buffer");
        return false;
    }

    encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
    if !encoder {
        log_error("Failed to create compute command encoder");
        return false;
    }

    MTLComputeCommandEncoder.setComputePipelineState(encoder, xx pipeline_compute);
    MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
    threads_per_grid := MTLSizeMake(ELEMENT_COUNT, 1, 1);
    threads_per_group := MTLSizeMake(ELEMENT_COUNT, 1, 1);
    MTLComputeCommandEncoder.dispatchThreads_threadsPerThreadgroup(encoder, threads_per_grid, threads_per_group);
    MTLCommandEncoder.endEncoding(cast(*MTLCommandEncoder) encoder);

    MTLCommandBuffer.commit(command_buffer);
    MTLCommandBuffer.waitUntilCompleted(command_buffer);

    for i: 0..ELEMENT_COUNT-1 {
        if out_data[i] != cast(u32) i {
            log_error("Compute validation failed: out[%] = %, expected %", i, out_data[i], i);
            return false;
        }
    }

    return true;
}

metal_example_with_window :: () -> (success: bool) {
    args_ok, args, is_set := parse_arguments(struct { singleframe: bool; test_readback: bool; });
    singleframe := args_ok && is_set.singleframe;
    test_readback := args_ok && is_set.test_readback;
    max_frames := ifx (singleframe || test_readback) then 1 else 0x7FFF_FFFF_FFFF_FFFF;
  
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

    if !run_compute_sanity_check(device, queue, compile_options) return false;

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
    // Convention: slot 0 is reserved for vertex-uniform bytes, slot 1 for vertex attributes.
    MTLVertexAttributeDescriptor.setBufferIndex(attr0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
    layout0 := MTLVertexBufferLayoutDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.layouts(vertex_desc), VERTEX_ATTRIBUTE_BUFFER_INDEX);
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
        if test_readback time_value = 1.0;

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
        if !drawable continue;

        drawable_size := CAMetalLayer.drawableSize(swapchain);
        uniforms := Fragment_Shader_Uniforms.{
            u_resolution = .{ xx drawable_size.width, xx drawable_size.height },
            u_time = time_value,
        };
        dummy_uniform: u8 = 0;

        pass := MTLRenderPassDescriptor.renderPassDescriptor();
        color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
        {
          using color_attachment;
          setClearColor(color_attachment, clear_color);
          setLoadAction(color_attachment, .MTLLoadActionClear);
          setStoreAction(color_attachment, .MTLStoreActionStore);
          setTexture(color_attachment, CAMetalDrawable.texture(drawable));
        }

        command_buffer := MTLCommandQueue.commandBuffer(queue);
        {
          using encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
          setRenderPipelineState(encoder, xx pipeline);
          setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
          setVertexBytes_length_atIndex(encoder, *dummy_uniform, 1, VERTEX_UNIFORM_BUFFER_INDEX);
          setFragmentBytes_length_atIndex(encoder, *uniforms, size_of(Fragment_Shader_Uniforms), FRAGMENT_UNIFORM_BUFFER_INDEX);
          drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, 6);
          endEncoding(encoder);
        }
        MTLCommandBuffer.presentDrawable(command_buffer, xx drawable);
        MTLCommandBuffer.commit(command_buffer);
        
        // Check the values of the texture if we were called with -test_readback
        if test_readback {
            test_readback = false;
            MTLCommandBuffer.waitUntilCompleted(command_buffer);
            
            using readback_info: Readback_Info;
            bytes_per_row = cast(NSUInteger) drawable_size.width * 4;
            width  = cast(s32) drawable_size.width;
            height = cast(s32) drawable_size.height;
            pixels = NewArray(cast(s64)(bytes_per_row * drawable_size.height), u8);
            defer array_free(pixels);
            tex := cast(*MTLTexture) CAMetalDrawable.texture(drawable);
            region := MTLRegionMake2D(0, 0, xx width, xx height);
            MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(tex, pixels.data, bytes_per_row, region, 0);
            if !validate_metal_readback(readback_info) {
                return false;
            }
        }
        
        end = current_time_consensus();
        frame_index += 1;
    }
    
    return true;
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

Readback_Info :: struct {
  pixels: []u8;
  bytes_per_row: NSUInteger = 0;
  width: s32;
  height: s32;
}

READBACK_SAMPLE_POINTS :: Vector2.[
    .{ 0.5, 0.5 },
    .{ 0.25, 0.25 },
    .{ 0.75, 0.25 },
    .{ 0.25, 0.75 },
    .{ 0.75, 0.75 },
];

validate_metal_readback :: (using readback_info: Readback_Info) -> bool {
    sample_count := READBACK_SAMPLE_POINTS.count;
    non_black := 0;
    min_luma: float32 = 999.0;
    max_luma: float32 = -1.0;
    sum_luma: float32 = 0;

    for READBACK_SAMPLE_POINTS {
        px := clamp(cast(s32) floor(it.x * xx width), 0, width-1);
        py := clamp(cast(s32) floor(it.y * xx height), 0, height-1);

        offset := cast(s64) py * cast(s64) bytes_per_row + cast(s64) px * 4;
        p := pixels.data + offset;
        r := xx p[0] / 255.0;
        g := xx p[1] / 255.0;
        b := xx p[2] / 255.0;
        luma := cast(float32) (0.2126 * r + 0.7152 * g + 0.0722 * b);

        if luma > 0.02 non_black += 1;
        min_luma = min(min_luma, luma);
        max_luma = max(max_luma, luma);
        sum_luma += luma;
    }

    avg_luma := sum_luma / xx sample_count;
    log("READBACK_SUMMARY backend=metal samples=% non_black=% avg_luma=% min_luma=% max_luma=%",
        sample_count, non_black, avg_luma, min_luma, max_luma);

    ok := (non_black >= 2) && (max_luma > 0.05) && ((max_luma - min_luma) > 0.02);
    if !ok {
        log_error("READBACK_FAIL backend=metal");
    }
    return ok;
}


main :: () {
  Debug.init();
  if !metal_example_with_window() {
      exit(1);
  }
}
