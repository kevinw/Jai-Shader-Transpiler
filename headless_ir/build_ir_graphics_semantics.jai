#load "./build_common.jai";

#run,stallable {
  set_build_options_dc(.{do_output=false, write_added_strings=false});
  simple_jst_build("ir_graphics_semantics_runner", "graphics_semantics_runner.jai");
}
