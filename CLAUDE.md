# zig-path

A CLI tool that displays the PATH environment variable split into individual directories with color coding and entry counts.

## Build & Test

```text
zig build          # build + install to ~/bin/paths
zig build test     # run unit tests
zig build run      # build and run
just               # runs test then build
```

Requires Zig 0.16.0-dev (uses the new `std.process.Init` main signature and `std.Io` abstraction).

## CI / Release

GitHub Actions workflow (`.github/workflows/release.yml`) runs on push to `main`:

- Uses `mlugg/setup-zig@v2` to install Zig 0.16-dev
- Runs tests, cross-compiles for `aarch64-macos` and `x86_64-macos`
- Publishes prebuilt binaries as a rolling `latest` GitHub Release
- Formula (`Formula/paths.rb`) downloads prebuilt binaries — no Zig dependency for Homebrew users

When updating the Zig version in the workflow, also update `build.zig` compatibility if needed.
After each release, update SHA256 checksums in `Formula/paths.rb` for the tap repo.

## Architecture

Single file: `main.zig`. No external dependencies.

### Modes

- **Default mode**: prints all unique PATH entries to stdout with color and file counts
- **Interactive mode** (`-i` flag): fullscreen TUI selector with scrolling, runs `ls -al <path> | less` on Enter
- **Duplicate mode** (`-d`/`--duplicate` flag): disables duplicate suppression, marks repeated entries with 🔄. Works in both default and interactive modes.
- **Shadow mode** (`-s`/`--shadow` flag): lists executables found in multiple PATH directories, with right-aligned names in light red and colored directory paths

### Key functions

- `main()` — entry point, parses flags via `std.process.Args.Iterator.init(init.minimal.args)`
- `printEntry()` — prints a single PATH entry with colors and optional duplicate marker (used in default mode)
- `renderList()` — draws the interactive list with ANSI codes (used in interactive mode)
- `interactiveMode()` — main loop: raw terminal mode, keypress handling, scrolling
- `shadowMode()` — scans all PATH dirs for executables, finds duplicates across dirs, prints formatted output
- `writeColoredPath()` — writes a path with appropriate color (shared by shadow mode output)
- `collectPaths()` — splits PATH, optionally deduplicates, returns paths and duplicate flags
- `runLs()` — spawns `sh -c "ls -al '<path>' | less"` via `std.process.spawn()`
- `countEntries()` — counts non-directory entries in a path (shows file count next to each entry)
- `findSpecialPrefix()` — matches paths starting with /opt/homebrew, /opt/workbrew, /opt/zerobrew
- `shortenHome()` — replaces $HOME prefix with `~`
- `detectTerminalHeight()` — gets terminal rows via `ioctl` with `TIOCGWINSZ`
- `readKey()` — reads stdin and classifies keypresses (up/down/enter/quit/other)

### Color scheme

- Yellow: paths under $HOME (entire path colored)
- Blue: special prefix portion (/opt/homebrew etc), rest in default color
- White + strikethrough: non-existent directories (with cross mark)
- Light red: executable names in shadow mode
- Dim: file count suffix `(N)`
- Reverse + bold: selected item in interactive mode

### Interactive mode details

- Terminal raw mode via `std.posix.tcgetattr`/`tcsetattr`
- Terminal height via `std.c.ioctl` with `TIOCGWINSZ`
- Direct stdout writes via `std.c.write` (bypasses buffering)
- Direct stdin reads via `std.c.read`
- Navigation: arrow keys, j/k, Enter to inspect, q/Esc to quit
- Scrolling: viewport adjusts when selection moves beyond visible area

### Zig 0.16 API notes

- `std.ArrayList(T)` is unmanaged — pass allocator to `append(gpa, ...)` and `deinit(gpa)`
- Initialize with `.empty` instead of `.init(gpa)`
- `std.StringHashMap` still uses `.init(gpa)` and `.deinit()` (managed)
- Main signature: `pub fn main(init: std.process.Init) !void`
- Init fields: `init.io` (Io), `init.gpa` (allocator), `init.environ_map` (env vars), `init.minimal.args`
- Args: `init.minimal.args` -> `std.process.Args.Iterator.init()`
- Process spawn: `std.process.spawn(io, .{ .argv = &.{...} })`
- Dir open: `Io.Dir.openDirAbsolute(io, path, .{ .iterate = true })`
- Buffered stdout: `Io.File.Writer` with `.init(.stdout(), io, &buf)`
- `posix.winsize` fields: `.row`, `.col`, `.xpixel`, `.ypixel`
