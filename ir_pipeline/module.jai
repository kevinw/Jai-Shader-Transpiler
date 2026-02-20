#scope_module

#import "Basic";
#import "Compiler";
#import "Program_Print";
#import "String";
#import "Hash_Table";

append :: inline (builder: *String_Builder, strings: ..string) {
  for strings append(builder, it);
}

#load "backend_shared.jai";
#load "external_toolchain.jai";
#load "ir_shared.jai";
#load "ir_lowering.jai";
#load "ir_normalize.jai";
#load "spirv_text_backend.jai";
#load "spv_types.jai";
