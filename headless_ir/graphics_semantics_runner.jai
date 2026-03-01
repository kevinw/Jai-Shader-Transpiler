#import "Basic";
#import "Math";
#import "String";
#import "Metal";
#import "Objective_C";

#import,file "../module.jai";
#load "headless_test_tools.jai";

WINDOW_W :: 128;
WINDOW_H :: 128;
VERTEX_UNIFORM_BUFFER_INDEX :: 0;
VERTEX_ATTRIBUTE_BUFFER_INDEX :: 1;

Graphics_Test_Vertex_In :: struct {
  a_pos: Vector2; @semantic_ATTRIBUTE0
}

Graphics_Test_Vertex_Out :: struct {
  position: Vector4; @semantic_SV_Position
}

Graphics_Test_Fragment_Out :: struct {
  out_color: Vector4; @semantic_SV_Target0
}

sample_2d :: (texture_index: u32, sampler_index: u32, uv: Vector2) -> Vector4 {
  _ = texture_index;
  _ = sampler_index;
  _ = uv;
  return .{};
}

graphics_test_red_triangle_vertex :: (using input: Graphics_Test_Vertex_In) -> Graphics_Test_Vertex_Out {
  using out: Graphics_Test_Vertex_Out;
  position = Vector4.{a_pos.x, a_pos.y, 0.0, 1.0};
  return out;
} @vertex_shader

graphics_test_red_triangle_fragment :: (using input: Graphics_Test_Vertex_Out) -> Graphics_Test_Fragment_Out {
  _ = input;
  using out: Graphics_Test_Fragment_Out;
  out_color = Vector4.{1.0, 0.0, 0.0, 1.0};
  return out;
} @fragment_shader

graphics_test_return_note_fragment :: (using input: Graphics_Test_Vertex_Out) -> Vector4 @SV_Target {
  _ = input;
  return Vector4.{1.0, 0.0, 0.0, 1.0};
} @fragment_shader

Graphics_Bindless_Vertex_Out :: struct {
  position: Vector4; @semantic_SV_Position
  uv: Vector2; @semantic_TEXCOORD0
}

Graphics_Bindless_Params :: struct {
  texture_index: u32;
  sampler_index: u32;
}

graphics_test_bindless_vertex :: (using input: Graphics_Test_Vertex_In) -> Graphics_Bindless_Vertex_Out {
  using out: Graphics_Bindless_Vertex_Out;
  position = Vector4.{a_pos.x, a_pos.y, 0.0, 1.0};
  uv = Vector2.{(a_pos.x + 1.0) * 0.5, (a_pos.y + 1.0) * 0.5};
  return out;
} @vertex_shader

graphics_test_bindless_fragment :: (using input: Graphics_Bindless_Vertex_Out, params: Graphics_Bindless_Params) -> Graphics_Test_Fragment_Out {
  using out: Graphics_Test_Fragment_Out;
  out_color = sample_2d(params.texture_index, params.sampler_index, input.uv);
  return out;
} @fragment_shader

graphics_test_nested_return_fragment :: (using input: Graphics_Bindless_Vertex_Out, params: Graphics_Bindless_Params) -> Graphics_Test_Fragment_Out {
  using out: Graphics_Test_Fragment_Out;
  debug := Vector4.{min(1.0, cast(float) params.texture_index), min(1.0, cast(float) params.sampler_index), 0.0, 1.0};
  if (params.texture_index & 1) != 0 {
    out_color = debug;
    return out;
  }
  if true {
    out_color = Vector4.{input.uv.x, input.uv.y, 0.0, 1.0};
    return out;
  }
  out_color = sample_2d(params.texture_index, params.sampler_index, input.uv);
  return out;
} @fragment_shader

Graphics_Nested_Resource_Leaf :: struct {
  values: *u32;
}

Graphics_Nested_Resource_Root :: struct {
  leaf: Graphics_Nested_Resource_Leaf;
}

graphics_test_nested_resource_fragment :: (using input: Graphics_Bindless_Vertex_Out, resources: Graphics_Nested_Resource_Root) -> Graphics_Test_Fragment_Out {
  using out: Graphics_Test_Fragment_Out;
  v := resources.leaf.values[0] & 1;
  if v == 0 {
    out_color = Vector4.{1.0, 0.0, 0.0, 1.0};
  } else {
    out_color = Vector4.{0.0, 1.0, 0.0, 1.0};
  }
  return out;
} @fragment_shader

Graphics_Instance_Vertex_In :: struct {
  a_pos: Vector2; @semantic_ATTRIBUTE0
  vertex_id: u32; @semantic_SV_VertexID
  instance_id: u32; @semantic_SV_InstanceID
}

Graphics_Instance_Vertex_Out :: struct {
  position: Vector4; @semantic_SV_Position
  color: Vector4; @semantic_COLOR0
}

Graphics_Instance_Fragment_Out :: struct {
  out_color: Vector4; @semantic_SV_Target0
}

graphics_test_instance_id_vertex :: (using input: Graphics_Instance_Vertex_In) -> Graphics_Instance_Vertex_Out {
  using out: Graphics_Instance_Vertex_Out;
  _ = vertex_id;
  scale: float = 0.45;
  offset_x: float = -0.45;
  if instance_id != 0 offset_x = 0.45;
  position = Vector4.{a_pos.x * scale + offset_x, a_pos.y * scale, 0.0, 1.0};
  if instance_id == 0 {
    color = Vector4.{1.0, 0.0, 0.0, 1.0};
  } else {
    color = Vector4.{0.0, 1.0, 0.0, 1.0};
  }
  return out;
} @vertex_shader

graphics_test_instance_id_fragment :: (using input: Graphics_Instance_Vertex_Out) -> Graphics_Instance_Fragment_Out {
  using out: Graphics_Instance_Fragment_Out;
  out_color = input.color;
  return out;
} @fragment_shader

cross2 :: (a: Vector2, b: Vector2) -> float {
  return a.x * b.y - a.y * b.x;
}

point_in_triangle :: (p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool {
  ab := b - a;
  bc := c - b;
  ca := a - c;
  ap := p - a;
  bp := p - b;
  cp := p - c;

  w0 := cross2(ab, ap);
  w1 := cross2(bc, bp);
  w2 := cross2(ca, cp);

  has_neg := (w0 < 0.0) || (w1 < 0.0) || (w2 < 0.0);
  has_pos := (w0 > 0.0) || (w1 > 0.0) || (w2 > 0.0);
  return !(has_neg && has_pos);
}

pixel_index :: (x: s32, y: s32, w: s32) -> s64 {
  return cast(s64) ((y * w + x) * 4);
}

build_cpu_reference_red_triangle :: (pixels: [] u8, width: s32, height: s32) -> s64 {
  for y: 0..height-1 {
    for x: 0..width-1 {
      idx := pixel_index(x, y, width);
      pixels[idx + 0] = 0;
      pixels[idx + 1] = 0;
      pixels[idx + 2] = 0;
      pixels[idx + 3] = 255;
    }
  }

  a := Vector2.{-0.80, -0.75};
  b := Vector2.{ 0.80, -0.75};
  c := Vector2.{ 0.00,  0.80};

  red_count: s64 = 0;
  inv_w := 1.0 / cast(float) width;
  inv_h := 1.0 / cast(float) height;
  for y: 0..height-1 {
    for x: 0..width-1 {
      p := Vector2.{
        x = (cast(float) x + 0.5) * inv_w * 2.0 - 1.0,
        y = (cast(float) y + 0.5) * inv_h * 2.0 - 1.0,
      };
      if !point_in_triangle(p, a, b, c) continue;
      idx := pixel_index(x, y, width);
      pixels[idx + 0] = 255;
      pixels[idx + 1] = 0;
      pixels[idx + 2] = 0;
      pixels[idx + 3] = 255;
      red_count += 1;
    }
  }

  return red_count;
}

count_gpu_red_pixels :: (pixels: [] u8, width: s32, height: s32) -> s64 {
  red_count: s64 = 0;
  for y: 0..height-1 {
    for x: 0..width-1 {
      idx := pixel_index(x, y, width);
      r := pixels[idx + 0];
      g := pixels[idx + 1];
      b := pixels[idx + 2];
      if r >= 200 && g <= 40 && b <= 40 red_count += 1;
    }
  }
  return red_count;
}

count_gpu_green_pixels :: (pixels: [] u8, width: s32, height: s32) -> s64 {
  green_count: s64 = 0;
  for y: 0..height-1 {
    for x: 0..width-1 {
      idx := pixel_index(x, y, width);
      r := pixels[idx + 0];
      g := pixels[idx + 1];
      b := pixels[idx + 2];
      if g >= 200 && r <= 40 && b <= 40 green_count += 1;
    }
  }
  return green_count;
}

validate_sample :: (pixels: [] u8, x: s32, y: s32, width: s32, expect_red: bool) {
  idx := pixel_index(x, y, width);
  r := pixels[idx + 0];
  g := pixels[idx + 1];
  b := pixels[idx + 2];

  if expect_red {
    if !(r >= 220 && g <= 40 && b <= 40) {
      fail("Expected red pixel at (%,%) but got rgb=(%,%,%)", x, y, r, g, b);
    }
    return;
  }

  if !(r <= 30 && g <= 30 && b <= 30) {
    fail("Expected black pixel at (%,%) but got rgb=(%,%,%)", x, y, r, g, b);
  }
}

validate_sample_green :: (pixels: [] u8, x: s32, y: s32, width: s32) {
  idx := pixel_index(x, y, width);
  r := pixels[idx + 0];
  g := pixels[idx + 1];
  b := pixels[idx + 2];
  if !(g >= 220 && r <= 40 && b <= 40) {
    fail("Expected green pixel at (%,%) but got rgb=(%,%,%)", x, y, r, g, b);
  }
}

validate_sample_blue :: (pixels: [] u8, x: s32, y: s32, width: s32) {
  idx := pixel_index(x, y, width);
  r := pixels[idx + 0];
  g := pixels[idx + 1];
  b := pixels[idx + 2];
  if !(b >= 220 && r <= 40 && g <= 40) {
    fail("Expected blue pixel at (%,%) but got rgb=(%,%,%)", x, y, r, g, b);
  }
}

log_nserror :: (label: string, error: *NSError) -> bool {
  if error == null return false;
  ns_description := NSError.localizedDescription(error);
  if ns_description {
    log_error("%: %", label, to_string(NSString.UTF8String(ns_description)));
  } else {
    log_error("%: (NSError with no description)", label);
  }
  return true;
}

run_red_triangle_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_red_triangle_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_red_triangle_fragment);
  check_contains(vertex_source, "vertex", "red triangle vertex metal");
  check_contains(fragment_source, "fragment", "red triangle fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  queue := MTLDevice.newCommandQueue(device);
  if !queue fail("Failed to create Metal command queue");
  defer release(queue);

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile vertex metal source", error) || !vertex_lib {
    fail("Failed to compile vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile fragment metal source", error) || !fragment_lib {
    fail("Failed to compile fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  vertex_desc := MTLVertexDescriptor.vertexDescriptor();
  defer release(vertex_desc);
  attr0 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.attributes(vertex_desc), 0);
  MTLVertexAttributeDescriptor.setFormat(attr0, .MTLVertexFormatFloat2);
  MTLVertexAttributeDescriptor.setOffset(attr0, 0);
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
  MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_desc, .MTLPixelFormatRGBA8Unorm);

  error = null;
  pipeline := MTLDevice.newRenderPipelineStateWithDescriptor_error(device, pipeline_desc, *error);
  if log_nserror("Failed to create render pipeline", error) || !pipeline {
    fail("Failed to create render pipeline");
  }
  defer release(pipeline);

  texture_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatRGBA8Unorm,
                                                                                                  cast(NSUInteger) WINDOW_W,
                                                                                                  cast(NSUInteger) WINDOW_H,
                                                                                                  NO);
  defer release(texture_desc);
  MTLTextureDescriptor.setUsage(texture_desc, .MTLTextureUsageRenderTarget | .MTLTextureUsageShaderRead);
  MTLTextureDescriptor.setStorageMode(texture_desc, .MTLStorageModeShared);
  color_tex := cast(*MTLTexture) MTLDevice.newTextureWithDescriptor(device, texture_desc);
  if !color_tex fail("Failed to create render target texture");
  defer release(color_tex);

  verts := Vector2.[
    Vector2.{-0.80, -0.75},
    Vector2.{ 0.80, -0.75},
    Vector2.{ 0.00,  0.80},
  ];
  vertex_buffer := MTLDevice.newBufferWithBytes_length_options(device, *verts, verts.count * size_of(Vector2), .MTLResourceStorageModeShared);
  if !vertex_buffer fail("Failed to create vertex buffer");
  defer release(vertex_buffer);

  pass := MTLRenderPassDescriptor.renderPassDescriptor();
  color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
  MTLRenderPassColorAttachmentDescriptor.setTexture(color_attachment, xx color_tex);
  MTLRenderPassColorAttachmentDescriptor.setLoadAction(color_attachment, .MTLLoadActionClear);
  MTLRenderPassColorAttachmentDescriptor.setStoreAction(color_attachment, .MTLStoreActionStore);
  MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, MTLClearColorMake(0.0, 0.0, 0.0, 1.0));

  command_buffer := MTLCommandQueue.commandBuffer(queue);
  if !command_buffer fail("Failed to create command buffer");

  encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
  if !encoder fail("Failed to create render command encoder");
  MTLRenderCommandEncoder.setRenderPipelineState(encoder, xx pipeline);
  MTLRenderCommandEncoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
  dummy_uniform: u8 = 0;
  MTLRenderCommandEncoder.setVertexBytes_length_atIndex(encoder, *dummy_uniform, 1, VERTEX_UNIFORM_BUFFER_INDEX);
  MTLRenderCommandEncoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3);
  MTLRenderCommandEncoder.endEncoding(encoder);

  MTLCommandBuffer.commit(command_buffer);
  MTLCommandBuffer.waitUntilCompleted(command_buffer);

  bytes_per_row := cast(NSUInteger) WINDOW_W * 4;
  gpu_pixels := NewArray(cast(s64) (bytes_per_row * WINDOW_H), u8);
  defer array_free(gpu_pixels);
  region := MTLRegionMake2D(0, 0, cast(NSUInteger) WINDOW_W, cast(NSUInteger) WINDOW_H);
  MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(color_tex, gpu_pixels.data, bytes_per_row, region, 0);

  cpu_pixels := NewArray(cast(s64) (WINDOW_W * WINDOW_H * 4), u8);
  defer array_free(cpu_pixels);
  cpu_red_count := build_cpu_reference_red_triangle(cpu_pixels, WINDOW_W, WINDOW_H);
  gpu_red_count := count_gpu_red_pixels(gpu_pixels, WINDOW_W, WINDOW_H);

  diff := gpu_red_count - cpu_red_count;
  if diff < 0 diff = -diff;
  if diff > 220 {
    fail("Red triangle coverage mismatch: cpu=% gpu=% diff=%", cpu_red_count, gpu_red_count, diff);
  }

  validate_sample(gpu_pixels, 64, 48, WINDOW_W, true);
  validate_sample(gpu_pixels, 10, 10, WINDOW_W, false);
  validate_sample(gpu_pixels, 118, 10, WINDOW_W, false);
  validate_sample(gpu_pixels, 64, 118, WINDOW_W, false);

  log("[OK] graphics_red_triangle (gpu_red=% cpu_red=%)", gpu_red_count, cpu_red_count);
}

run_return_note_fragment_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_red_triangle_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_return_note_fragment);
  check_contains(vertex_source, "vertex", "return-note vertex metal");
  check_contains(fragment_source, "fragment", "return-note fragment metal");
  check_contains(fragment_source, "[[color(0)]]", "return-note fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile return-note vertex metal source", error) || !vertex_lib {
    fail("Failed to compile return-note vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile return-note fragment metal source", error) || !fragment_lib {
    fail("Failed to compile return-note fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find return-note vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find return-note fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  log("[OK] graphics_return_note_fragment");
}

build_cpu_reference_instance_id_pair :: (pixels: [] u8, width: s32, height: s32) -> (red_count: s64, green_count: s64) {
  for y: 0..height-1 {
    for x: 0..width-1 {
      idx := pixel_index(x, y, width);
      pixels[idx + 0] = 0;
      pixels[idx + 1] = 0;
      pixels[idx + 2] = 0;
      pixels[idx + 3] = 255;
    }
  }

  scale: float = 0.45;
  base_a := Vector2.{-0.80, -0.75};
  base_b := Vector2.{ 0.80, -0.75};
  base_c := Vector2.{ 0.00,  0.80};
  left_offset: float = -0.45;
  right_offset: float = 0.45;

  left_a := Vector2.{base_a.x * scale + left_offset, base_a.y * scale};
  left_b := Vector2.{base_b.x * scale + left_offset, base_b.y * scale};
  left_c := Vector2.{base_c.x * scale + left_offset, base_c.y * scale};
  right_a := Vector2.{base_a.x * scale + right_offset, base_a.y * scale};
  right_b := Vector2.{base_b.x * scale + right_offset, base_b.y * scale};
  right_c := Vector2.{base_c.x * scale + right_offset, base_c.y * scale};

  red_count_local: s64 = 0;
  green_count_local: s64 = 0;
  inv_w := 1.0 / cast(float) width;
  inv_h := 1.0 / cast(float) height;
  for y: 0..height-1 {
    for x: 0..width-1 {
      p := Vector2.{
        x = (cast(float) x + 0.5) * inv_w * 2.0 - 1.0,
        y = (cast(float) y + 0.5) * inv_h * 2.0 - 1.0,
      };

      idx := pixel_index(x, y, width);
      if point_in_triangle(p, left_a, left_b, left_c) {
        pixels[idx + 0] = 255;
        pixels[idx + 1] = 0;
        pixels[idx + 2] = 0;
        pixels[idx + 3] = 255;
        red_count_local += 1;
      } else if point_in_triangle(p, right_a, right_b, right_c) {
        pixels[idx + 0] = 0;
        pixels[idx + 1] = 255;
        pixels[idx + 2] = 0;
        pixels[idx + 3] = 255;
        green_count_local += 1;
      }
    }
  }
  return red_count_local, green_count_local;
}

run_instance_id_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_instance_id_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_instance_id_fragment);
  check_contains(vertex_source, "instance_id", "instance-id vertex metal");
  check_contains(fragment_source, "fragment", "instance-id fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  queue := MTLDevice.newCommandQueue(device);
  if !queue fail("Failed to create Metal command queue");
  defer release(queue);

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile instance-id vertex metal source", error) || !vertex_lib {
    fail("Failed to compile instance-id vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile instance-id fragment metal source", error) || !fragment_lib {
    fail("Failed to compile instance-id fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  vertex_desc := MTLVertexDescriptor.vertexDescriptor();
  defer release(vertex_desc);
  attr0 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.attributes(vertex_desc), 0);
  MTLVertexAttributeDescriptor.setFormat(attr0, .MTLVertexFormatFloat2);
  MTLVertexAttributeDescriptor.setOffset(attr0, 0);
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
  MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_desc, .MTLPixelFormatRGBA8Unorm);

  error = null;
  pipeline := MTLDevice.newRenderPipelineStateWithDescriptor_error(device, pipeline_desc, *error);
  if log_nserror("Failed to create instance-id render pipeline", error) || !pipeline {
    fail("Failed to create instance-id render pipeline");
  }
  defer release(pipeline);

  texture_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatRGBA8Unorm,
                                                                                                  cast(NSUInteger) WINDOW_W,
                                                                                                  cast(NSUInteger) WINDOW_H,
                                                                                                  NO);
  defer release(texture_desc);
  MTLTextureDescriptor.setUsage(texture_desc, .MTLTextureUsageRenderTarget | .MTLTextureUsageShaderRead);
  MTLTextureDescriptor.setStorageMode(texture_desc, .MTLStorageModeShared);
  color_tex := cast(*MTLTexture) MTLDevice.newTextureWithDescriptor(device, texture_desc);
  if !color_tex fail("Failed to create instance-id render target texture");
  defer release(color_tex);

  verts := Vector2.[
    Vector2.{-0.80, -0.75},
    Vector2.{ 0.80, -0.75},
    Vector2.{ 0.00,  0.80},
  ];
  vertex_buffer := MTLDevice.newBufferWithBytes_length_options(device, *verts, verts.count * size_of(Vector2), .MTLResourceStorageModeShared);
  if !vertex_buffer fail("Failed to create instance-id vertex buffer");
  defer release(vertex_buffer);

  pass := MTLRenderPassDescriptor.renderPassDescriptor();
  color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
  MTLRenderPassColorAttachmentDescriptor.setTexture(color_attachment, xx color_tex);
  MTLRenderPassColorAttachmentDescriptor.setLoadAction(color_attachment, .MTLLoadActionClear);
  MTLRenderPassColorAttachmentDescriptor.setStoreAction(color_attachment, .MTLStoreActionStore);
  MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, MTLClearColorMake(0.0, 0.0, 0.0, 1.0));

  command_buffer := MTLCommandQueue.commandBuffer(queue);
  if !command_buffer fail("Failed to create instance-id command buffer");

  encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
  if !encoder fail("Failed to create instance-id render command encoder");
  MTLRenderCommandEncoder.setRenderPipelineState(encoder, xx pipeline);
  MTLRenderCommandEncoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
  dummy_uniform: u8 = 0;
  MTLRenderCommandEncoder.setVertexBytes_length_atIndex(encoder, *dummy_uniform, 1, VERTEX_UNIFORM_BUFFER_INDEX);
  MTLRenderCommandEncoder.drawPrimitives_vertexStart_vertexCount_instanceCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3, 2);
  MTLRenderCommandEncoder.endEncoding(encoder);

  MTLCommandBuffer.commit(command_buffer);
  MTLCommandBuffer.waitUntilCompleted(command_buffer);

  bytes_per_row := cast(NSUInteger) WINDOW_W * 4;
  gpu_pixels := NewArray(cast(s64) (bytes_per_row * WINDOW_H), u8);
  defer array_free(gpu_pixels);
  region := MTLRegionMake2D(0, 0, cast(NSUInteger) WINDOW_W, cast(NSUInteger) WINDOW_H);
  MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(color_tex, gpu_pixels.data, bytes_per_row, region, 0);

  cpu_pixels := NewArray(cast(s64) (WINDOW_W * WINDOW_H * 4), u8);
  defer array_free(cpu_pixels);
  cpu_red_count, cpu_green_count := build_cpu_reference_instance_id_pair(cpu_pixels, WINDOW_W, WINDOW_H);
  gpu_red_count := count_gpu_red_pixels(gpu_pixels, WINDOW_W, WINDOW_H);
  gpu_green_count := count_gpu_green_pixels(gpu_pixels, WINDOW_W, WINDOW_H);

  red_diff := gpu_red_count - cpu_red_count;
  if red_diff < 0 red_diff = -red_diff;
  green_diff := gpu_green_count - cpu_green_count;
  if green_diff < 0 green_diff = -green_diff;
  if red_diff > 160 || green_diff > 160 {
    fail("Instance-id coverage mismatch: cpu(red=% green=%) gpu(red=% green=%)", cpu_red_count, cpu_green_count, gpu_red_count, gpu_green_count);
  }

  validate_sample(gpu_pixels, 36, 57, WINDOW_W, true);
  validate_sample_green(gpu_pixels, 92, 57, WINDOW_W);
  validate_sample(gpu_pixels, 64, 57, WINDOW_W, false);
  validate_sample(gpu_pixels, 64, 112, WINDOW_W, false);

  log("[OK] graphics_instance_id_pair (gpu_red=% cpu_red=% gpu_green=% cpu_green=%)", gpu_red_count, cpu_red_count, gpu_green_count, cpu_green_count);
}

run_bindless_sample_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_bindless_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_bindless_fragment);
  check_contains(vertex_source, "vertex", "bindless vertex metal");
  check_contains(fragment_source, "fragment", "bindless fragment metal");
  check_contains(fragment_source, "sample(", "bindless fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  queue := MTLDevice.newCommandQueue(device);
  if !queue fail("Failed to create Metal command queue");
  defer release(queue);

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile bindless vertex metal source", error) || !vertex_lib {
    fail("Failed to compile bindless vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile bindless fragment metal source", error) || !fragment_lib {
    fail("Failed to compile bindless fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find bindless vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find bindless fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  vertex_desc := MTLVertexDescriptor.vertexDescriptor();
  defer release(vertex_desc);
  attr0 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(MTLVertexDescriptor.attributes(vertex_desc), 0);
  MTLVertexAttributeDescriptor.setFormat(attr0, .MTLVertexFormatFloat2);
  MTLVertexAttributeDescriptor.setOffset(attr0, 0);
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
  MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_desc, .MTLPixelFormatRGBA8Unorm);

  error = null;
  pipeline := MTLDevice.newRenderPipelineStateWithDescriptor_error(device, pipeline_desc, *error);
  if log_nserror("Failed to create bindless render pipeline", error) || !pipeline {
    fail("Failed to create bindless render pipeline");
  }
  defer release(pipeline);

  // Upload a 2x2 non-uniform texture (left=red, right=green) and sample through bindless descriptors.
  sample_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatRGBA8Unorm, 2, 2, NO);
  defer release(sample_desc);
  MTLTextureDescriptor.setUsage(sample_desc, .MTLTextureUsageShaderRead);
  MTLTextureDescriptor.setStorageMode(sample_desc, .MTLStorageModeShared);
  sample_tex := cast(*MTLTexture) MTLDevice.newTextureWithDescriptor(device, sample_desc);
  if !sample_tex fail("Failed to create bindless sample texture");
  defer release(sample_tex);

  sample_pixels := u8.[
    255, 0,   0, 255,   0, 255, 0, 255,
    255, 0,   0, 255,   0, 255, 0, 255,
  ];
  sample_region := MTLRegionMake2D(0, 0, 2, 2);
  MTLTexture.replaceRegion_mipmapLevel_withBytes_bytesPerRow(sample_tex, sample_region, 0, *sample_pixels, 8);

  sampler_desc := objc_init(objc_alloc(MTLSamplerDescriptor));
  defer release(sampler_desc);
  MTLSamplerDescriptor.setMinFilter(sampler_desc, .MTLSamplerMinMagFilterNearest);
  MTLSamplerDescriptor.setMagFilter(sampler_desc, .MTLSamplerMinMagFilterNearest);
  MTLSamplerDescriptor.setMipFilter(sampler_desc, .MTLSamplerMipFilterNotMipmapped);
  MTLSamplerDescriptor.setSAddressMode(sampler_desc, .MTLSamplerAddressModeClampToEdge);
  MTLSamplerDescriptor.setTAddressMode(sampler_desc, .MTLSamplerAddressModeClampToEdge);
  sampler_state := MTLDevice.newSamplerStateWithDescriptor(device, sampler_desc);
  if !sampler_state fail("Failed to create bindless sampler state");
  defer release(sampler_state);

  bindless_params := Graphics_Bindless_Params.{texture_index = 0, sampler_index = 0};
  bindless_params_buffer := MTLDevice.newBufferWithBytes_length_options(device, *bindless_params, size_of(Graphics_Bindless_Params), .MTLResourceStorageModeShared);
  if !bindless_params_buffer fail("Failed to create bindless params buffer");
  defer release(bindless_params_buffer);

  texture_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatRGBA8Unorm,
                                                                                                  cast(NSUInteger) WINDOW_W,
                                                                                                  cast(NSUInteger) WINDOW_H,
                                                                                                  NO);
  defer release(texture_desc);
  MTLTextureDescriptor.setUsage(texture_desc, .MTLTextureUsageRenderTarget | .MTLTextureUsageShaderRead);
  MTLTextureDescriptor.setStorageMode(texture_desc, .MTLStorageModeShared);
  color_tex := cast(*MTLTexture) MTLDevice.newTextureWithDescriptor(device, texture_desc);
  if !color_tex fail("Failed to create bindless render target texture");
  defer release(color_tex);

  verts := Vector2.[
    Vector2.{-0.80, -0.75},
    Vector2.{ 0.80, -0.75},
    Vector2.{ 0.00,  0.80},
  ];
  vertex_buffer := MTLDevice.newBufferWithBytes_length_options(device, *verts, verts.count * size_of(Vector2), .MTLResourceStorageModeShared);
  if !vertex_buffer fail("Failed to create bindless vertex buffer");
  defer release(vertex_buffer);

  pass := MTLRenderPassDescriptor.renderPassDescriptor();
  color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(MTLRenderPassDescriptor.colorAttachments(pass), 0);
  MTLRenderPassColorAttachmentDescriptor.setTexture(color_attachment, xx color_tex);
  MTLRenderPassColorAttachmentDescriptor.setLoadAction(color_attachment, .MTLLoadActionClear);
  MTLRenderPassColorAttachmentDescriptor.setStoreAction(color_attachment, .MTLStoreActionStore);
  MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, MTLClearColorMake(0.0, 0.0, 0.0, 1.0));

  command_buffer := MTLCommandQueue.commandBuffer(queue);
  if !command_buffer fail("Failed to create bindless command buffer");

  encoder := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
  if !encoder fail("Failed to create bindless render command encoder");
  MTLRenderCommandEncoder.setRenderPipelineState(encoder, xx pipeline);
  MTLRenderCommandEncoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
  MTLRenderCommandEncoder.setFragmentBuffer_offset_atIndex(encoder, xx bindless_params_buffer, 0, 0);
  MTLRenderCommandEncoder.setFragmentTexture_atIndex(encoder, xx sample_tex, 1);
  MTLRenderCommandEncoder.setFragmentSamplerState_atIndex(encoder, xx sampler_state, 0);

  MTLRenderCommandEncoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3);
  MTLRenderCommandEncoder.endEncoding(encoder);

  MTLCommandBuffer.commit(command_buffer);
  MTLCommandBuffer.waitUntilCompleted(command_buffer);

  bytes_per_row := cast(NSUInteger) WINDOW_W * 4;
  gpu_pixels := NewArray(cast(s64) (bytes_per_row * WINDOW_H), u8);
  defer array_free(gpu_pixels);
  region := MTLRegionMake2D(0, 0, cast(NSUInteger) WINDOW_W, cast(NSUInteger) WINDOW_H);
  MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(color_tex, gpu_pixels.data, bytes_per_row, region, 0);

  validate_sample(gpu_pixels, 56, 48, WINDOW_W, true);
  validate_sample_green(gpu_pixels, 72, 48, WINDOW_W);
  validate_sample(gpu_pixels, 10, 10, WINDOW_W, false);
  validate_sample(gpu_pixels, 118, 10, WINDOW_W, false);
  validate_sample(gpu_pixels, 64, 118, WINDOW_W, false);

  // Verify out-of-range bindless indices are clamped in generated shader code.
  bindless_params_oob := Graphics_Bindless_Params.{texture_index = 999, sampler_index = 999};
  bindless_params_oob_buffer := MTLDevice.newBufferWithBytes_length_options(device, *bindless_params_oob, size_of(Graphics_Bindless_Params), .MTLResourceStorageModeShared);
  if !bindless_params_oob_buffer fail("Failed to create bindless out-of-range params buffer");
  defer release(bindless_params_oob_buffer);

  command_buffer_oob := MTLCommandQueue.commandBuffer(queue);
  if !command_buffer_oob fail("Failed to create bindless out-of-range command buffer");
  encoder_oob := MTLCommandBuffer.renderCommandEncoderWithDescriptor(command_buffer_oob, pass);
  if !encoder_oob fail("Failed to create bindless out-of-range render command encoder");
  MTLRenderCommandEncoder.setRenderPipelineState(encoder_oob, xx pipeline);
  MTLRenderCommandEncoder.setVertexBuffer_offset_atIndex(encoder_oob, xx vertex_buffer, 0, VERTEX_ATTRIBUTE_BUFFER_INDEX);
  MTLRenderCommandEncoder.setFragmentBuffer_offset_atIndex(encoder_oob, xx bindless_params_oob_buffer, 0, 0);
  MTLRenderCommandEncoder.setFragmentTexture_atIndex(encoder_oob, xx sample_tex, 1);
  MTLRenderCommandEncoder.setFragmentSamplerState_atIndex(encoder_oob, xx sampler_state, 0);
  // Index 15 in 16-wide arrays maps to explicit slots texture(16), sampler(15).
  MTLRenderCommandEncoder.setFragmentTexture_atIndex(encoder_oob, xx sample_tex, 16);
  MTLRenderCommandEncoder.setFragmentSamplerState_atIndex(encoder_oob, xx sampler_state, 15);
  MTLRenderCommandEncoder.drawPrimitives_vertexStart_vertexCount(encoder_oob, .MTLPrimitiveTypeTriangle, 0, 3);
  MTLRenderCommandEncoder.endEncoding(encoder_oob);
  MTLCommandBuffer.commit(command_buffer_oob);
  MTLCommandBuffer.waitUntilCompleted(command_buffer_oob);

  gpu_pixels_oob := NewArray(cast(s64) (bytes_per_row * WINDOW_H), u8);
  defer array_free(gpu_pixels_oob);
  MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(color_tex, gpu_pixels_oob.data, bytes_per_row, region, 0);
  validate_sample(gpu_pixels_oob, 56, 48, WINDOW_W, true);
  validate_sample_green(gpu_pixels_oob, 72, 48, WINDOW_W);
  validate_sample(gpu_pixels_oob, 10, 10, WINDOW_W, false);

  log("[OK] graphics_bindless_sample");
}

run_nested_return_pair_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_bindless_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_nested_return_fragment);
  check_contains(vertex_source, "vertex", "nested-return vertex metal");
  check_contains(fragment_source, "fragment", "nested-return fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile nested-return vertex metal source", error) || !vertex_lib {
    fail("Failed to compile nested-return vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile nested-return fragment metal source", error) || !fragment_lib {
    fail("Failed to compile nested-return fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find nested-return vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find nested-return fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  log("[OK] graphics_nested_return_pair");
}

run_nested_resource_container_case_metal :: () {
  init_objective_c();
  init_metal();

  vertex_source := get_transpiled(.METAL, graphics_test_bindless_vertex);
  fragment_source := get_transpiled(.METAL, graphics_test_nested_resource_fragment);
  check_contains(vertex_source, "vertex", "nested-resource vertex metal");
  check_contains(fragment_source, "fragment", "nested-resource fragment metal");

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  defer release(compile_options);
  MTLCompileOptions.setLanguageVersion(compile_options, .MTLLanguageVersion2_1);

  error: *NSError = null;
  vertex_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(vertex_source), compile_options, *error);
  if log_nserror("Failed to compile nested-resource vertex metal source", error) || !vertex_lib {
    fail("Failed to compile nested-resource vertex metal source");
  }
  defer release(vertex_lib);

  error = null;
  fragment_lib := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(fragment_source), compile_options, *error);
  if log_nserror("Failed to compile nested-resource fragment metal source", error) || !fragment_lib {
    fail("Failed to compile nested-resource fragment metal source");
  }
  defer release(fragment_lib);

  fn_vertex := cast(*MTLFunction) MTLLibrary.newFunctionWithName(vertex_lib, NSString.getTempString("VertexMain"));
  if !fn_vertex fail("Failed to find nested-resource vertex entry point 'VertexMain'");
  defer release(fn_vertex);

  fn_fragment := cast(*MTLFunction) MTLLibrary.newFunctionWithName(fragment_lib, NSString.getTempString("FragmentMain"));
  if !fn_fragment fail("Failed to find nested-resource fragment entry point 'FragmentMain'");
  defer release(fn_fragment);

  log("[OK] graphics_nested_resource_container");
}

main :: () {
  #if OS != .MACOS {
    log("Skipping graphics semantics runner on % (Metal-only test).", OS);
    return;
  }

  run_red_triangle_case_metal();
  run_return_note_fragment_case_metal();
  run_instance_id_case_metal();
  run_bindless_sample_case_metal();
  run_nested_return_pair_case_metal();
  run_nested_resource_container_case_metal();
  log("Passed 6 graphics semantics cases.");
}
