/*
Note! this isn't actually really useful. but it shows that you can just run the jai shader code as-is.
*/

#import "Basic";
#import "Math";
#import "Command_Line";
using,except(NO) SDL :: #import "SDL";

#import,file "../module.jai";
#load "glsl_shaders.jai";
#load "example_common.jai";

WINDOW_WIDTH  :: 1080;
WINDOW_HEIGHT :: 720;
CPU_WIDTH     :: 360;
CPU_HEIGHT    :: 240;

mask_r :: 0x000000ff;
mask_g :: 0x0000ff00;
mask_b :: 0x00ff0000;
mask_a :: 0xff000000;

clamp01 :: (x: float) -> float {
  if x < 0.0 return 0.0;
  if x > 1.0 return 1.0;
  return x;
}

to_u8 :: (x: float) -> u8 {
  return cast(u8) (255.0 * clamp01(x));
}

render_tiles_to_pixels :: (pixels: [] u8, width: s32, height: s32, time: float) {
  resolution := Vector2.{ cast(float) width, cast(float) height };
  for y: 0..height-1 {
    for x: 0..width-1 {
      frag_coord := Vector2.{ cast(float) x + 0.5, cast(float) y + 0.5 };
      color := tiles_fragment_shader({gl_FragCoord = {frag_coord.x, frag_coord.y, 0, 0}}, 
        {u_resolution=resolution, u_time=time}
      ).out_color;
      i := cast(s64) ((y * width + x) * 4);
      pixels[i + 0] = to_u8(color.x);
      pixels[i + 1] = to_u8(color.y);
      pixels[i + 2] = to_u8(color.z);
      pixels[i + 3] = to_u8(color.w);
    }
  }
}

main :: () {
  args_ok, args, is_set := parse_arguments(struct { single_frame: bool; test_readback: bool; });
  single_frame := args_ok && is_set.single_frame;
  test_readback := args_ok && is_set.test_readback;
  max_frames: s64 = ifx (single_frame || test_readback) then 1 else 0x7FFF_FFFF_FFFF_FFFF;

  if SDL_Init(SDL_INIT_VIDEO) != 0 {
    log_error("SDL_Init failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  defer SDL_Quit();

  window := SDL_CreateWindow("CPU Tiles Example", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, 0);
  if !window {
    log_error("SDL_CreateWindow failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  defer SDL_DestroyWindow(window);

  renderer := SDL_CreateRenderer(window, -1, .PRESENTVSYNC);
  if !renderer {
    log_error("SDL_CreateRenderer failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  defer SDL_DestroyRenderer(renderer);

  if SDL_RenderSetLogicalSize(renderer, CPU_WIDTH, CPU_HEIGHT) != 0 {
    log_error("SDL_RenderSetLogicalSize failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  _ = SDL_RenderSetIntegerScale(renderer, .SDL_TRUE);

  cpu_pixels := NewArray(cast(s64) (CPU_WIDTH * CPU_HEIGHT * 4), u8);
  defer array_free(cpu_pixels);

  surface := SDL_CreateRGBSurfaceFrom(cpu_pixels.data, CPU_WIDTH, CPU_HEIGHT, 32, CPU_WIDTH * 4, mask_r, mask_g, mask_b, mask_a);
  if !surface {
    log_error("SDL_CreateRGBSurfaceFrom failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  defer SDL_FreeSurface(surface);

  texture := SDL_CreateTextureFromSurface(renderer, surface);
  if !texture {
    log_error("SDL_CreateTextureFromSurface failed: %", to_string(SDL_GetError()));
    exit(1);
  }
  defer SDL_DestroyTexture(texture);

  quit := false;
  start := current_time_consensus();
  end := start;
  time_value: float;
  frame_index: s64 = 0;

  while !quit && frame_index < max_frames {
    dt := to_float64_seconds(end - start);
    start = current_time_consensus();

    time_value += cast(float) dt;
    if test_readback time_value = 1.0;

    event: SDL_Event;
    while SDL_PollEvent(*event) {
      if event.type == .SDL_QUIT quit = true;
    }

    render_tiles_to_pixels(cpu_pixels, CPU_WIDTH, CPU_HEIGHT, time_value);

    if test_readback {
      if !validate_readback_samples("cpu", cpu_pixels, CPU_WIDTH, CPU_HEIGHT, CPU_WIDTH * 4) {
        exit(1);
      }
    }

    if SDL_UpdateTexture(texture, null, cpu_pixels.data, CPU_WIDTH * 4) != 0 {
      log_error("SDL_UpdateTexture failed: %", to_string(SDL_GetError()));
      exit(1);
    }
    if SDL_RenderClear(renderer) != 0 {
      log_error("SDL_RenderClear failed: %", to_string(SDL_GetError()));
      exit(1);
    }
    if SDL_RenderCopy(renderer, texture, null, null) != 0 {
      log_error("SDL_RenderCopy failed: %", to_string(SDL_GetError()));
      exit(1);
    }
    SDL_RenderPresent(renderer);

    end = current_time_consensus();
    frame_index += 1;
  }
}
