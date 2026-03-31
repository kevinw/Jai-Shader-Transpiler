# IR / SPIR-V TODOs

This file tracks concrete IR/SPIR-V backend limitations that are still open.
Completed items were moved to `IR_DONE.md`.

Direction note:
- Incrementally prefer carrying richer Compiler AST/type information through lowering where practical, instead of encoding behavior through hardcoded strings and mirrored IR type/operator tables. Start by removing string-sentinel decisions (for example `"<operator_not_supported>"` checks) in favor of typed operator handling.
- Prefer Compiler module enums/nodes (`Operator_Type`, `Code_Node` forms, `Type_Info`) over duplicated string encodings whenever the data stays in-compiler-pass.
