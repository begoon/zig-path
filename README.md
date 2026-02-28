# paths

A CLI tool that displays your PATH directories with color coding, file counts, and an interactive selector.

## Features

- Color-coded output: **yellow** for home directories, **blue** for Homebrew prefixes, **strikethrough** for missing paths
- File counts for each directory
- Deduplicates PATH entries
- Interactive mode with a fullscreen TUI selector

## Install

### Homebrew (macOS)

```sh
brew tap begoon/tap
brew install paths
```

Prebuilt binaries for Apple Silicon and Intel Macs are published automatically
via GitHub Releases — no Zig toolchain required.

### From source

Requires [Zig](https://ziglang.org/) 0.16+.

```sh
zig build
```

The binary is installed to `~/bin/paths` (default) or `zig-out/bin/paths` with `--prefix zig-out`.

## Usage

```sh
# Display all PATH directories
paths

# Interactive mode — browse and inspect directories
paths -i
```

### Default mode

Prints each unique PATH directory with color coding and file counts:

```text
/opt/homebrew/bin (42)
/opt/homebrew/sbin (3)
~/.local/bin (7)
/usr/local/bin (128)
/usr/bin (983)
```

### Configuration

Custom "special prefixes" (shown in blue) can be set in `~/.paths.json`:

```json
{"special_prefixes": ["/opt/homebrew", "/usr/local"]}
```

If the file is missing, defaults are used: `/opt/homebrew`, `/opt/workbrew`, `/opt/zerobrew`.

### Interactive mode (`-i`)

A fullscreen TUI selector. Navigate with arrow keys or `j`/`k`, press `Enter` to run `ls -al <path> | less`, and `q` or `Esc` to quit.

### Re-tap

```sh
brew untap begoon/tap
brew tap begoon/tap
brew install paths
```

## License

[MIT](LICENSE)
