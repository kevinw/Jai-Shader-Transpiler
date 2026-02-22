Build_Timing_Totals :: struct {
  typechecked_message_s: float64;
  phase_message_s: float64;

  known_proc_collect_s: float64;
  declaration_collect_s: float64;
  pending_resolution_s: float64;

  pair_emit_s: float64;
  single_emit_s: float64;
  lookup_emit_s: float64;

  typechecked_message_count: s64;
  phase_message_count: s64;
  emitted_pair_count: s64;
  emitted_single_count: s64;

  spv_single_total_s: float64;
  spv_pair_total_s: float64;
  spv_lower_s: float64;
  spv_normalize_s: float64;
  spv_emit_text_s: float64;
  spv_write_files_s: float64;
  spv_read_files_s: float64;
  spv_assemble_s: float64;
  spv_optimize_s: float64;
  spv_validate_s: float64;
  spv_cross_s: float64;
}

set_build_timings_enabled :: (enabled: bool) {
  build_timings_enabled = enabled;
}

timed :: (seconds_value: *float64, code: Code) #expand {
  start: Apollo_Time;
  if build_timings_enabled start = current_time_monotonic();
  
  #insert,scope(code) code;
  
  if build_timings_enabled && seconds_value != null {
    seconds_value.* += to_float64_seconds(current_time_monotonic() - start);
  }
}

log_timings :: (using totals: Build_Timing_Totals) {
  log("[timing][build][plugin] typechecked msgs=% total=%s collect_known=%s collect_decl=%s resolve_pending=%s",
    typechecked_message_count,
    typechecked_message_s,
    known_proc_collect_s,
    declaration_collect_s,
    pending_resolution_s);
  log("[timing][build][plugin] phase msgs=% total=%s pair_emit=%s single_emit=%s emit_lookup=%s emitted_pairs=% emitted_singles=%",
    phase_message_count,
    phase_message_s,
    pair_emit_s,
    single_emit_s,
    lookup_emit_s,
    emitted_pair_count,
    emitted_single_count);
  log("[timing][build][plugin][spv] wall_single=%s wall_pair=%s worker_sum_lower=%s worker_sum_normalize=%s worker_sum_emit_spvasm=%s worker_sum_write_files=%s worker_sum_read_files=%s worker_sum_assemble=%s worker_sum_optimize=%s worker_sum_validate=%s worker_sum_cross=%s",
    spv_single_total_s,
    spv_pair_total_s,
    spv_lower_s,
    spv_normalize_s,
    spv_emit_text_s,
    spv_write_files_s,
    spv_read_files_s,
    spv_assemble_s,
    spv_optimize_s,
    spv_validate_s,
    spv_cross_s);
  
}

#scope_file

build_timings_enabled: bool;
