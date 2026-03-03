#load "./build_common.jai";

#run,stallable {
  set_build_options_dc(.{do_output=false, write_added_strings=false});
  log("Building compute_semantics_runner.jai...");
  simple_jst_build("ir_compute_semantics_runner", "compute_semantics_runner.jai");
}
