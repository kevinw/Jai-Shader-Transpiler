# Jai-Shader-Transpiler

Metaprogram for converting Jai functions to shaders.

To build examples and run all tests:

```
jai -quiet build.jai - -run_tests
```

## Structure

The metaprogram in Jai_To_Shader.jai watches compiler messages and sees Jai
functions noted with @compute_shader or @fragment_shader or @vertex_shader.
It then emits string constants into the build which can be retrieved with 
the `get_transpiled` function.
