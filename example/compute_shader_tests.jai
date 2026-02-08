Compute_Test_In :: struct {
  thread_id: UVector3; @inbuilt_thread_position_in_grid
}

compute_write_indices :: (using in: Compute_Test_In, out: *u32) {
  if thread_id.x < 64 {
    out[thread_id.x] = thread_id.x;
  }
} @metal @compute_shader
