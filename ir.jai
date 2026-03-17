USE_NATIVE_DLL :: false;
#if USE_NATIVE_DLL {
    #import,dir "./modules/ir_pipe";
} else {
    #import,dir "ir_pipeline";
}
