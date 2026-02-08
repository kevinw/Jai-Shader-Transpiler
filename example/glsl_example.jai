#import "Basic";
#import "Math";
Input :: #import "Input";
#import "Window_Creation";
#import "GL";
#import "Command_Line";

#import,file "../module.jai"; // #import "Jai-Shader-Transpiler" in your code.

#load "glsl_shaders.jai";
#load "array_shader_tests.jai";
#load "example_gl_backend.jai";

READBACK_SAMPLE_POINTS :: Vector2.[
  .{ 0.5, 0.5 },
  .{ 0.25, 0.25 },
  .{ 0.75, 0.25 },
  .{ 0.25, 0.75 },
  .{ 0.75, 0.75 },
];

validate_gl_readback :: (width: s32, height: s32) -> bool {
  sample_count := READBACK_SAMPLE_POINTS.count;
  non_black := 0;
  min_luma: float32 = 999.0;
  max_luma: float32 = -1.0;
  sum_luma: float32 = 0;

  pixel: [4] u8;
  for READBACK_SAMPLE_POINTS {
    px := clamp(cast(s32) floor(it.x * xx width), 0, width-1);
    py := clamp(cast(s32) floor(it.y * xx height), 0, height-1);
    glReadPixels(px, py, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, *pixel);

    r := xx pixel[0] / 255.0;
    g := xx pixel[1] / 255.0;
    b := xx pixel[2] / 255.0;
    luma := cast(float32) (0.2126 * r + 0.7152 * g + 0.0722 * b);

    if luma > 0.02 non_black += 1;
    min_luma = min(min_luma, luma);
    max_luma = max(max_luma, luma);
    sum_luma += luma;
  }

  avg_luma := sum_luma / xx sample_count;
  log("READBACK_SUMMARY backend=glsl samples=% non_black=% avg_luma=% min_luma=% max_luma=%",
      sample_count, non_black, avg_luma, min_luma, max_luma);

  ok := (non_black >= 2) && (max_luma > 0.05) && ((max_luma - min_luma) > 0.02);
  if !ok {
    log_error("READBACK_FAIL backend=glsl");
  }
  return ok;
}

main :: () {
  args_ok, args, is_set := parse_arguments(struct { singleframe: bool; test_readback: bool; });
  singleframe := args_ok && is_set.singleframe;
  test_readback := args_ok && is_set.test_readback;
  max_frames := ifx (singleframe || test_readback) then 1 else 0x7FFF_FFFF_FFFF_FFFF;
  
  window := create_window(1080, 720, "FancyTiles");
  load_gl(window);

  //log("Vertex Shader:\n%\n\n=========\n", tiles_vertex_shader_string);
  //log("Fragment Shader:\n%", tiles_fragment_shader_string);
  
  // Force array support test shaders to typecheck and generate.
  _ := array_support_vertex_shader(.{}, .{});
  _ = array_support_fragment_shader(.{}, .{});
  _ = array_support_vertex_shader_string;
  _ = array_support_fragment_shader_string;

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
  vscode := tiles_vertex_shader_string;
  fscode := tiles_fragment_shader_string;
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
      if !validate_gl_readback(1080, 720) exit(1);
    }

    swap_buffers(window);
    end = current_time_consensus();
    frame_index += 1;
  }

  glDeleteBuffers(1, *buffer);
  glDeleteVertexArrays(1, *vao);
  glDeleteProgram(shader);
}
