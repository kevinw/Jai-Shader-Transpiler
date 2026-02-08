Compute_Test_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
}

compute_write_indices :: (using in: Compute_Test_In, values: *u32) {
  if thread_id.x < 64 {
    values[thread_id.x] = thread_id.x;
  }
} @compute_shader
