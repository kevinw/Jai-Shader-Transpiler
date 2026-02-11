#import "Basic";
#import "Math";
Input :: #import "Input";
#import "Window_Creation";
#import "GL";
#import "Command_Line";

#import,file "../module.jai"; // #import "Jai-Shader-Transpiler" in your code.

#load "glsl_shaders.jai";
#load "array_shader_tests.jai";
#load "compute_shader_tests.jai";
#load "example_gl_backend.jai";
#load "example_common.jai";

run_gl_compute_sanity_check :: () -> bool {
  #if OS == .MACOS {
    log("Skipping GLSL compute runtime check on macOS (OpenGL 4.1 does not support compute shaders).");
    return true;
  }

  program := glCreateProgram();
  compute_module := glCreateShader(GL_COMPUTE_SHADER);
  defer glDeleteProgram(program);
  defer glDeleteShader(compute_module);

  source := get_transpiled(.OPENGL_GLSL, compute_write_indices);
  glShaderSource(compute_module, 1, *source.data, xx *source.count);
  glCompileShader(compute_module);

  err: s32;
  glGetShaderiv(compute_module, GL_COMPILE_STATUS, *err);
  if xx err == GL_FALSE {
    log_error("Compute Shader Compilation Failed:");
    length: u32;
    glGetShaderiv(compute_module, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetShaderInfoLog(compute_module, length, xx 0, info);
    log_error("%", string.{ length, info });
    free(info);
    return false;
  }

  glAttachShader(program, compute_module);
  glLinkProgram(program);
  glGetProgramiv(program, GL_LINK_STATUS, *err);
  if xx err == GL_FALSE {
    log_error("Compute Program Linking Failed:");
    length: u32;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetProgramInfoLog(program, length, xx 0, info);
    log_error("%", string.{ length, info });
    free(info);
    return false;
  }

  ELEMENT_COUNT :: 64;
  ssbo_data: [ELEMENT_COUNT] u32;
  for i: 0..ELEMENT_COUNT-1 ssbo_data[i] = 0xFFFF_FFFF;

  ssbo: u32;
  glGenBuffers(1, *ssbo);
  defer glDeleteBuffers(1, *ssbo);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo);
  glBufferData(GL_SHADER_STORAGE_BUFFER, ELEMENT_COUNT * size_of(u32), *ssbo_data, GL_STATIC_DRAW);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, ssbo);

  glUseProgram(program);
  glDispatchCompute(1, 1, 1);
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT | GL_BUFFER_UPDATE_BARRIER_BIT);
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, ELEMENT_COUNT * size_of(u32), *ssbo_data);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);

  for i: 0..ELEMENT_COUNT-1 {
    if ssbo_data[i] != cast(u32) i {
      log_error("GLSL compute validation failed: out[%] = %, expected %", i, ssbo_data[i], i);
      return false;
    }
  }

  log("GLSL compute validation succeeded.");
  return true;
}

main :: () {
  _ = get_transpiled(.OPENGL_GLSL, tiles_vertex_shader);
  _ = get_transpiled(.OPENGL_GLSL, tiles_fragment_shader);
  _ = get_transpiled(.OPENGL_GLSL, array_support_vertex_shader);
  _ = get_transpiled(.OPENGL_GLSL, array_support_fragment_shader);
  _ = get_transpiled(.OPENGL_GLSL, compute_write_indices);

  args_ok, args, is_set := parse_arguments(struct { singleframe: bool; test_readback: bool; });
  singleframe := args_ok && is_set.singleframe;
  test_readback := args_ok && is_set.test_readback;
  max_frames := ifx (singleframe || test_readback) then 1 else 0x7FFF_FFFF_FFFF_FFFF;
  
  window := create_window(1080, 720, "FancyTiles");
  load_gl(window);
  if !run_gl_compute_sanity_check() exit(1);

  //log("Vertex Shader:\n%\n\n=========\n", tiles_vertex_shader_string);
  //log("Fragment Shader:\n%", tiles_fragment_shader_string);
  
  // Force array support test shaders to typecheck and generate.
  _ := array_support_vertex_shader(.{}, .{});
  _ = array_support_fragment_shader(.{}, .{});
  _ = get_transpiled(.OPENGL_GLSL, array_support_vertex_shader);
  _ = get_transpiled(.OPENGL_GLSL, array_support_fragment_shader);

  vao: u32;
  buffer: u32;
  shader: u32;
  
  data := Vector2.[
    Vector2.{ -1, -1 },
    Vector2.{  1, -1 },
    Vector2.{  1,  1 },
    Vector2.{ -1, -1 },
    Vector2.{  1,  1 },
    Vector2.{ -1,  1 },
  ];

  glGenVertexArrays(1, *vao);
  glBindVertexArray(vao);
  glGenBuffers(1, *buffer);
  glBindBuffer(GL_ARRAY_BUFFER, buffer);
  glBufferData(GL_ARRAY_BUFFER, 6 * size_of(Vector2), *data, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), xx 0);
  glEnableVertexAttribArray(0);

  err: s32;
  shader = glCreateProgram();
  vert_module := glCreateShader(GL_VERTEX_SHADER);
  frag_module := glCreateShader(GL_FRAGMENT_SHADER);
  vscode := get_transpiled(.OPENGL_GLSL, tiles_vertex_shader);
  fscode := get_transpiled(.OPENGL_GLSL, tiles_fragment_shader);
  glShaderSource(vert_module, 1, *vscode.data, xx *vscode.count);
  glShaderSource(frag_module, 1, *fscode.data, xx *fscode.count);
  glCompileShader(vert_module);
  glCompileShader(frag_module);

  glGetShaderiv(vert_module, GL_COMPILE_STATUS, *err);
  if xx err == GL_FALSE {
    print("Vertex Shader Compilation Failed:\n");
    length: u32;
    glGetShaderiv(vert_module, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetShaderInfoLog(vert_module, length, xx 0, info);
    info_str: string;
    info_str.data = xx info;
    info_str.count = length;
    print("%\n", info_str);
    free(info);
    exit(1);
  }
  glGetShaderiv(frag_module, GL_COMPILE_STATUS, *err);
  if xx err == GL_FALSE {
    log_error("Fragment Shader Compilation Failed:");
    length: u32;
    glGetShaderiv(frag_module, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetShaderInfoLog(frag_module, length, xx 0, info);
    log_error("%", string.{ length, info });
    free(info);
    exit(1);
  }

  glAttachShader(shader, vert_module);
  glAttachShader(shader, frag_module);
  glLinkProgram(shader);
  glGetProgramiv(shader, GL_LINK_STATUS, *err);
  if xx err == GL_FALSE {
    log_error("Program Linking Failed:");
    length: u32;
    glGetProgramiv(shader, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetProgramInfoLog(shader, length, xx 0, info);
    log_error("%", string.{ length, info });
    free(info);
    exit(1);
  }
  glDetachShader(shader, vert_module);
  glDetachShader(shader, frag_module);
  glDeleteShader(vert_module);
  glDeleteShader(frag_module);
  glUseProgram(shader);
  
  resolution_location := glGetUniformLocation(shader, "u_resolution");
  time_location := glGetUniformLocation(shader, "u_time");

  glUniform2f(resolution_location, 1080, 720);

  quit := false;
  start : Apollo_Time;
  end : Apollo_Time;
  dt : float64 = ---;
  time_value : float32;
  frame_index := 0;
  

  while !quit && frame_index < max_frames {
    dt = to_float64_seconds(end - start);
    start = current_time_consensus();
    
    time_value += xx dt;
    if test_readback time_value = 1.0;

    Input.update_window_events();
    for Input.events_this_frame {
      if it.type == {
        case .QUIT; quit = true;
      }
    }

    glClearColor(0.3, 0.2, 0.3, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glUniform1f(time_location, time_value);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    if test_readback {
      glFinish();
      readback_pixels := NewArray(cast(s64) (1080 * 720 * 4), u8);
      defer array_free(readback_pixels);
      glReadPixels(0, 0, 1080, 720, GL_RGBA, GL_UNSIGNED_BYTE, readback_pixels.data);
      if !validate_readback_samples("glsl", readback_pixels, 1080, 720, 1080 * 4) exit(1);
    }

    swap_buffers(window);
    end = current_time_consensus();
    frame_index += 1;
  }

  glDeleteBuffers(1, *buffer);
  glDeleteVertexArrays(1, *vao);
  glDeleteProgram(shader);
}
