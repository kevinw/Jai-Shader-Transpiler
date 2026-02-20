message_loop :: (w: Workspace, plugins: []*Metaprogram_Plugin, verbose_build_progress: bool=false) -> bool {
  ok := false;
  message_count: s64 = 0;
  last_progress_log_time := current_time_monotonic();
  while true {
    message := compiler_wait_for_message();
    message_count += 1;
    for plugins it.message(it, message);
    if verbose_build_progress {
      now := current_time_monotonic();
      elapsed_since_log := to_float64_seconds(now - last_progress_log_time);
      if elapsed_since_log >= 0.5 {
        log("[build] workspace % progress: % messages, last kind=%", w, message_count, message.kind);
        last_progress_log_time = now;
      }
    }
    if message.kind == .COMPLETE {
      ok = message.(*Message_Complete).error_code == 0;
      break;
    }
  }
  return ok;
}
