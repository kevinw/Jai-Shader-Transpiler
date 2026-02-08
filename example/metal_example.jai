#import "Basic";
using,except(NO) SDL :: #import "SDL";
#import "Metal";
#import "Objective_C";

main :: () {
    init_objective_c();
    init_metal();

    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
    SDL_Init(SDL_INIT_VIDEO);

    // Create an application window with the following settings:
    window := SDL_CreateWindow("SDL metal", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 480, SDL_WINDOW_ALLOW_HIGHDPI);
    renderer := SDL_CreateRenderer(window, -1, .PRESENTVSYNC);

    swapchain := cast(*CAMetalLayer) SDL_RenderGetMetalLayer(renderer);
    device := CAMetalLayer.device(swapchain);

    queue := MTLDevice.newCommandQueue(device);

    color := MTLClearColorMake(0, 0, 0, 1);

    // Check that the window was successfully created
    if window == null {
        // In the case that the window could not be made...
        print("Could not create window: %\n", to_string(SDL_GetError()));
        return;
    }

    exit := false;
    last_time := current_time_monotonic();
    while !exit {
        now := current_time_monotonic();
        dt := to_float64_seconds(now - last_time);
        last_time = now;
        
        event: SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == {
                case SDL_QUIT;
                    exit = true;
                case SDL_KEYUP;
                    if event.key.keysym.sym == SDLK_ESCAPE exit = true;
            }
        }

        color.red = ifx color.red > 1.0 then cast(float64)0.0 else color.red + dt;

        pool := objc_init(objc_alloc(NSAutoreleasePool));
        defer NSAutoreleasePool.drain(pool);

        surface := CAMetalLayer.nextDrawable(swapchain);

        // Ugh, my eyes are bleeding!
        pass := MTLRenderPassDescriptor.renderPassDescriptor();
        color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
        MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, color);
        MTLRenderPassAttachmentDescriptor.setLoadAction(color_attachment, MTLLoadActionClear);
        MTLRenderPassAttachmentDescriptor.setStoreAction(color_attachment, MTLStoreActionStore);
        MTLRenderPassAttachmentDescriptor.setTexture(color_attachment, surface.texture(surface));

        buffer := MTLCommandQueue.commandBuffer(queue);
        encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(buffer, pass);
        MTLRenderCommandEncoder.endEncoding(encoder);
        MTLCommandBuffer.presentDrawable(buffer, xx surface);
        MTLCommandBuffer.commit(buffer);
    }

    SDL_DestroyRenderer(renderer);
    // Close and destroy the window
    SDL_DestroyWindow(window);

    // Clean up
    SDL_Quit();
}
