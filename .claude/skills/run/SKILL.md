---
name: run
description: Build and run paths with given flags
disable-model-invocation: true
allowed-tools: Bash
argument-hint: [flags]
---

Build with `zig build` then run `~/bin/paths $ARGUMENTS` and show the output.

If no arguments are provided, run without flags.
