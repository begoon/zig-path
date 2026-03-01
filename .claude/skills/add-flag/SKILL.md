---
name: add-flag
description: Add a new CLI flag to the paths tool
disable-model-invocation: true
argument-hint: <short-flag> <long-flag> <description>
---

Add a new CLI flag to `main.zig`. Follow the existing patterns:

1. Add a `var` for the flag state in `main()` alongside `interactive`, `shadow`, `show_duplicates`
2. Add flag matching in the `while (args_iter.next())` loop using `std.mem.eql`
3. Add the flag to the help text (using `\\` multiline string syntax, aligned with existing options)
4. Implement the flag's behavior
5. Update `CLAUDE.md` and `README.md` to document the new flag
6. Build with `zig build` and run `zig build test` to verify

Reference the `-s`/`--shadow` and `-d`/`--duplicate` implementations as examples.
