Compute_Test_In :: struct {
  thread_id: UVector3; @inbuilt_thread_position_in_grid
}

compute_write_indices :: (using in: Compute_Test_In, values: *u32) {
  if thread_id.x < 64 {
    values[thread_id.x] = thread_id.x;
  }
} @metal @glsl @compute_shader
