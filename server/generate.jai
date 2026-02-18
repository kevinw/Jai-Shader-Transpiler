//
// Generates module.jai bindings for civetweb, a minimal C http server.
// 

RUN_AT_COMPILE_TIME :: true; 

#if RUN_AT_COMPILE_TIME {
    #run {
        set_build_options_dc(.{do_output = false});
        if !build() compiler_set_workspace_status(.FAILED);
    }
} else {
    main :: () { if !build() exit(1); }
}

build :: () -> bool {
    log("Generating civetweb bindings...");
    
    using opts: Generate_Bindings_Options;
    log_unsupported = true;
    generate_compile_time_struct_checks = false;  // ObjC interfaces have opaque layouts
    alias_original_enum_names = false; // omit enum aliases like MTLVertexFormatUChar2Normalized :: UChar2Normalized;
    array_add(*source_files,  "civetweb/include/civetweb.h");
    array_add(*libraries,     {filename="civetweb/libcivetweb.dylib", identifier="libcivetweb"});
    array_add(*path_fragments_to_treat_as_non_system_paths, "civetweb.h");
    
    return generate_bindings(opts, "module.jai");
}

#scope_file
#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
