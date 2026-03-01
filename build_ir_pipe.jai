#scope_file
BUILD_IS_FOR_IDE :: #exists(JAILS_DIAGNOSTICS_BUILD); // Whether the build is for the IDE's error display. (Jails language server runs the build to check for errors.)
OPTIMIZATION_TYPE :: Optimization_Type.VERY_OPTIMIZED; // .VERY_DEBUG

#run,stallable {
    set_build_options_dc(.{do_output=false, write_added_strings=false});
    build_ir_pipeline_dll();
}

build_ir_pipeline_dll :: () {
    output_name :: "ir_pipe";
    source_filename := "ir_pipeline/module.jai";
    
    workspace := compiler_create_workspace("ir_pipe");
    {
        using options := get_build_options(workspace);
        copy_commonly_propagated_fields(get_build_options(), *options);
        output_type = .DYNAMIC_LIBRARY;
        PLATFORM_DIR :: #run to_lower_copy(tprint("%", OS)); // windows, macos, linux, etc...
        output_path = tprint("modules/%/%", output_name, PLATFORM_DIR);
        File.make_directory_if_it_does_not_exist(output_path, recursive=true);
        output_executable_name = output_name;
        os_target   = OS;
        cpu_target  = CPU;
        backend = .LLVM;
        #if BUILD_IS_FOR_IDE output_type = .NO_OUTPUT;
        set_optimization(*options,  OPTIMIZATION_TYPE);
        array_bounds_check = .OFF;
        stack_trace = false;
        text_output_flags = 0;
        set_build_options(options, workspace);
    }
    
    plugins: [..]*Metaprogram_Plugin;
    jdll := JDLL.get_plugin();
    //array_add(*jdll.options.include_files, "ir_pipeline/public_structs.jai"); // TODO: once JDLL knows how to print structs/enums tagged with @jdll_export or something we don't need this.
    jdll.options.public_footer = #string END
    
#load "../../ir_pipeline/public_structs.jai";

    END;
    array_add(*plugins, jdll);
    
    intercept_flags: Intercept_Flags = 0;
    for plugins it.workspace = workspace;
    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);
    compiler_begin_intercept(workspace, intercept_flags);
    defer {
        compiler_end_intercept(workspace);
        for plugins if it.finish   it.finish  (it);
        for plugins if it.shutdown it.shutdown(it);
    }
    for plugins if it.add_source it.add_source(it);
        
    add_build_file(source_filename, workspace);
    
    ok := message_loop(workspace, plugins);
    if !ok exit(1);
    
    log("Built dynamic library and bindings at %", jdll.output.generated_module_filename);
}

#scope_file
#load "build_common.jai";
#import "Basic";
#import "Compiler";
#import "String";
File :: #import "File";
JDLL :: #import,dir "../JDLL";
