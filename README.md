# paths

A CLI tool that displays your PATH directories with color coding, file counts, and an interactive selector.

## Features

- Color-coded output: **yellow** for home directories, **blue** for Homebrew prefixes, **strikethrough** for missing paths
- File counts for each directory
- Deduplicates PATH entries
- Interactive mode with a fullscreen TUI selector

## Install

### Homebrew

```sh
brew tap begoon/tap
brew install paths
```

### From source

Requires [Zig](https://ziglang.org/) 0.16+.

```sh
zig build -Doptimize=ReleaseFast
```

The binary is installed to `zig-out/bin/paths`.

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

### Interactive mode (`-i`)

A fullscreen TUI selector. Navigate with arrow keys or `j`/`k`, press `Enter` to run `ls -al <path> | less`, and `q` or `Esc` to quit.

## License

[MIT](LICENSE)
