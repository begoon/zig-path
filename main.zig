const std = @import("std");
const Io = std.Io;
const posix = std.posix;
const build_options = @import("build_options");

const PROGRAM_NAME = "paths";

const default_special_prefixes = [_][]const u8{
    "/opt/homebrew",
    "/opt/workbrew",
    "/opt/zerobrew",
    "/usr/local",
};

const CONFIG_FILE = ".paths.json";

const LoadConfigResult = union(enum) {
    not_found,
    err,
    ok: []const []const u8,
};

fn loadConfig(gpa: std.mem.Allocator, home: []const u8, io: Io) LoadConfigResult {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, CONFIG_FILE }) catch return .not_found;

    const file = Io.Dir.openDirAbsolute(io, home, .{}) catch return .not_found;
    var dir = file;
    defer dir.close(io);

    const data = dir.readFileAlloc(io, CONFIG_FILE, gpa, Io.Limit.limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        else => {
            var stderr_buf: [512]u8 = undefined;
            var stderr_w: Io.File.Writer = .init(.stderr(), io, &stderr_buf);
            stderr_w.interface.print("error: cannot read {s}: {s}\n", .{ config_path, @errorName(err) }) catch {};
            stderr_w.interface.flush() catch {};
            return .err;
        },
    };

    const parsed = std.json.parseFromSlice(struct { special_prefixes: []const []const u8 }, gpa, data, .{}) catch {
        var stderr_buf: [512]u8 = undefined;
        var stderr_w: Io.File.Writer = .init(.stderr(), io, &stderr_buf);
        stderr_w.interface.print("error: invalid JSON in {s}\n", .{config_path}) catch {};
        stderr_w.interface.flush() catch {};
        return .err;
    };

    return .{ .ok = parsed.value.special_prefixes };
}

// ANSI escape codes
const RESET = "\x1b[0m";
const BLUE = "\x1b[34m";
const YELLOW = "\x1b[33m";
const LIGHT_RED = "\x1b[91m";
const WHITE = "\x1b[97m";
const DIM = "\x1b[2m";
const STRIKE = "\x1b[9m";
const REVERSE = "\x1b[7m";
const BOLD = "\x1b[1m";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const CLEAR_LINE = "\x1b[2K";
const CLEAR_SCREEN = "\x1b[2J";
const CURSOR_HOME = "\x1b[H";

/// Returns the length of a matching special prefix, or null if none match.
/// Only matches at path boundaries (exact match or followed by '/').
pub fn findSpecialPrefix(path: []const u8, prefixes: []const []const u8) ?usize {
    for (prefixes) |prefix| {
        if (path.len >= prefix.len and
            std.mem.eql(u8, path[0..prefix.len], prefix) and
            (path.len == prefix.len or path[prefix.len] == '/'))
        {
            return prefix.len;
        }
    }
    return null;
}

/// If path starts with home dir, returns the suffix after home and is_home=true.
/// Ensures match is at a path boundary.
pub fn shortenHome(path: []const u8, home: []const u8) struct { suffix: []const u8, is_home: bool } {
    if (home.len > 0 and path.len >= home.len and
        std.mem.eql(u8, path[0..home.len], home) and
        (path.len == home.len or path[home.len] == '/'))
    {
        return .{ .suffix = path[home.len..], .is_home = true };
    }
    return .{ .suffix = path, .is_home = false };
}

fn countEntries(io: Io, path: []const u8) struct { count: usize, exists: bool } {
    const dir = (if (std.fs.path.isAbsolute(path))
        Io.Dir.openDirAbsolute(io, path, .{ .iterate = true })
    else
        Io.Dir.cwd().openDir(io, path, .{ .iterate = true })) catch
        return .{ .count = 0, .exists = false };
    defer dir.close(io);

    var count: usize = 0;
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (entry.kind != .directory) {
            count += 1;
        }
    }
    return .{ .count = count, .exists = true };
}

fn printEntry(writer: anytype, io: Io, path: []const u8, home: []const u8, prefixes: []const []const u8, is_duplicate: bool) !void {
    const info = countEntries(io, path);
    const shortened = shortenHome(path, home);

    if (!info.exists) {
        try writer.writeAll(STRIKE);
        if (shortened.is_home) {
            try writer.writeAll(WHITE ++ "~");
            try writer.writeAll(shortened.suffix);
            try writer.writeAll(RESET);
        } else {
            try writer.writeAll(path);
            try writer.writeAll(RESET);
        }
        try writer.writeAll(" \xe2\x9d\x8c");
    } else if (shortened.is_home) {
        try writer.writeAll(YELLOW ++ "~");
        try writer.writeAll(shortened.suffix);
        try writer.writeAll(RESET);
    } else if (findSpecialPrefix(path, prefixes)) |prefix_len| {
        try writer.writeAll(BLUE);
        try writer.writeAll(path[0..prefix_len]);
        try writer.writeAll(RESET);
        try writer.writeAll(path[prefix_len..]);
    } else {
        try writer.writeAll(path);
    }

    try writer.print(DIM ++ " ({d})" ++ RESET, .{info.count});
    if (is_duplicate) {
        try writer.writeAll(" \xf0\x9f\x94\x84");
    }
    try writer.writeAll("\n");
}

fn detectTerminalHeight() u16 {
    var wsz: posix.winsize = .{ .row = 24, .col = 80, .xpixel = 0, .ypixel = 0 };
    const rc = std.c.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (rc == 0) return wsz.row;
    return 24;
}

fn enableRawMode() std.posix.termios {
    const orig = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
    var raw = orig;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw) catch unreachable;
    return orig;
}

fn disableRawMode(orig: std.posix.termios) void {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig) catch {};
}

fn writeAll(buf: []const u8) void {
    var offset: usize = 0;
    while (offset < buf.len) {
        const n = std.c.write(std.posix.STDOUT_FILENO, buf[offset..].ptr, buf.len - offset);
        if (n < 0) return;
        offset += @intCast(n);
    }
}

fn writeFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const v = std.fmt.bufPrint(&buf, fmt, args) catch return;
    writeAll(v);
}

fn readKey() enum { up, down, enter, quit, other } {
    var buf: [8]u8 = undefined;
    const rc = std.c.read(std.posix.STDIN_FILENO, &buf, buf.len);
    if (rc <= 0) return .quit;
    const n: usize = @intCast(rc);

    if (buf[0] == 'q' or buf[0] == 'Q') return .quit;
    if (buf[0] == 27) { // ESC
        if (n == 1) return .quit;
        if (n >= 3 and buf[1] == '[') {
            if (buf[2] == 'A') return .up;
            if (buf[2] == 'B') return .down;
        }
        return .other;
    }
    if (buf[0] == '\r' or buf[0] == '\n') return .enter;
    if (buf[0] == 'k' or buf[0] == 'K') return .up;
    if (buf[0] == 'j' or buf[0] == 'J') return .down;
    return .other;
}

fn renderList(
    paths: []const []const u8,
    duplicates: []const bool,
    home: []const u8,
    selected: usize,
    scroll_offset: usize,
    visible_count: usize,
    io: Io,
    prefixes: []const []const u8,
) void {
    writeAll(CURSOR_HOME);

    for (0..visible_count) |i| {
        const index = scroll_offset + i;
        writeAll(CLEAR_LINE);
        if (index < paths.len) {
            const path = paths[index];
            const info = countEntries(io, path);
            const shortened = shortenHome(path, home);

            if (index == selected) {
                writeAll(REVERSE ++ BOLD);
            }

            if (!info.exists) {
                writeAll(STRIKE);
                if (shortened.is_home) {
                    writeAll("~");
                    writeAll(shortened.suffix);
                } else {
                    writeAll(path);
                }
                writeAll(" \xe2\x9d\x8c");
            } else if (shortened.is_home) {
                if (index != selected) writeAll(YELLOW);
                writeAll("~");
                writeAll(shortened.suffix);
                if (index != selected) writeAll(RESET);
            } else if (findSpecialPrefix(path, prefixes)) |prefix_len| {
                if (index != selected) writeAll(BLUE);
                writeAll(path[0..prefix_len]);
                if (index != selected) writeAll(RESET);
                writeAll(path[prefix_len..]);
            } else {
                writeAll(path);
            }

            writeFmt(DIM ++ " ({d})" ++ RESET, .{info.count});
            if (duplicates.len > 0 and index < duplicates.len and duplicates[index]) {
                writeAll(" \xf0\x9f\x94\x84");
            }
            if (index == selected) {
                writeAll(RESET);
            }
        }
        writeAll("\r\n");
    }

    // Status line
    writeAll(CLEAR_LINE);
    writeFmt(DIM ++ " [{d}/{d}] \xe2\x86\x91\xe2\x86\x93/jk: navigate  \xe2\x86\xb5: ls -al  q: quit" ++ RESET, .{ selected + 1, paths.len });
}

fn runLs(path: []const u8, io: Io) void {
    writeAll(CLEAR_SCREEN ++ CURSOR_HOME ++ SHOW_CURSOR);

    var buf: [4096]u8 = undefined;
    const cmd = std.fmt.bufPrint(&buf, "ls -al '{s}' | less", .{path}) catch return;

    var child = std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", cmd },
    }) catch return;
    _ = child.wait(io) catch {};
}

fn interactiveMode(paths: []const []const u8, duplicates: []const bool, home: []const u8, io: Io, prefixes: []const []const u8) void {
    if (paths.len == 0) {
        writeAll("no " ++ PROGRAM_NAME ++ " found in PATH\n");
        return;
    }

    const height = detectTerminalHeight();
    const visible_count: usize = @min(paths.len, @as(usize, height) -| 2);

    const orig_termios = enableRawMode();
    defer disableRawMode(orig_termios);
    defer writeAll(SHOW_CURSOR ++ CLEAR_SCREEN ++ CURSOR_HOME);

    writeAll(HIDE_CURSOR ++ CLEAR_SCREEN);

    var selected: usize = 0;
    var scroll_offset: usize = 0;

    while (true) {
        renderList(paths, duplicates, home, selected, scroll_offset, visible_count, io, prefixes);

        switch (readKey()) {
            .up => {
                if (selected > 0) {
                    selected -= 1;
                    if (selected < scroll_offset) {
                        scroll_offset = selected;
                    }
                }
            },
            .down => {
                if (selected + 1 < paths.len) {
                    selected += 1;
                    if (selected >= scroll_offset + visible_count) {
                        scroll_offset = selected - visible_count + 1;
                    }
                }
            },
            .enter => {
                disableRawMode(orig_termios);
                runLs(paths[selected], io);
                _ = enableRawMode();
                writeAll(HIDE_CURSOR ++ CLEAR_SCREEN);
            },
            .quit => return,
            .other => {},
        }
    }
}

fn writeColoredPath(writer: anytype, path: []const u8, home: []const u8, prefixes: []const []const u8) !void {
    const shortened = shortenHome(path, home);
    if (shortened.is_home) {
        try writer.writeAll(YELLOW ++ "~");
        try writer.writeAll(shortened.suffix);
        try writer.writeAll(RESET);
    } else if (findSpecialPrefix(path, prefixes)) |prefix_len| {
        try writer.writeAll(BLUE);
        try writer.writeAll(path[0..prefix_len]);
        try writer.writeAll(RESET);
        try writer.writeAll(path[prefix_len..]);
    } else {
        try writer.writeAll(path);
    }
}

fn shadowMode(gpa: std.mem.Allocator, paths: []const []const u8, home: []const u8, io: Io, prefixes: []const []const u8) !void {
    // map from executable name -> list of directory paths containing it
    var exe_map = std.StringHashMap(std.ArrayList([]const u8)).init(gpa);
    defer {
        var it = exe_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(gpa);
        }
        exe_map.deinit();
    }

    // scan each PATH directory for executables
    for (paths) |dir_path| {
        const dir = (if (std.fs.path.isAbsolute(dir_path))
            Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true })
        else
            Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true })) catch continue;
        defer dir.close(io);

        var iter = dir.iterate();
        while (iter.next(io) catch null) |entry| {
            if (entry.kind == .directory) continue;
            // check if file is executable
            const stat = dir.statFile(io, entry.name, .{}) catch continue;
            if (stat.permissions.toMode() & 0o111 == 0) continue;
            const name_dupe = gpa.dupe(u8, entry.name) catch continue;
            const value = exe_map.getOrPut(name_dupe) catch {
                gpa.free(name_dupe);
                continue;
            };
            if (!value.found_existing) {
                value.value_ptr.* = .empty;
            } else {
                gpa.free(name_dupe);
            }
            // only add if this dir_path isn't already in the list
            var already = false;
            for (value.value_ptr.items) |existing| {
                if (std.mem.eql(u8, existing, dir_path)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                value.value_ptr.append(gpa, dir_path) catch continue;
            }
        }
    }

    const Shadow = struct { name: []const u8, dirs: []const []const u8 };

    // collect only executables that appear in multiple paths
    var shadows: std.ArrayList(Shadow) = .empty;
    defer shadows.deinit(gpa);

    var it = exe_map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.items.len > 1) {
            try shadows.append(gpa, .{ .name = entry.key_ptr.*, .dirs = entry.value_ptr.items });
        }
    }

    if (shadows.items.len == 0) return;

    // sort by name
    std.mem.sort(Shadow, shadows.items, {}, struct {
        fn lessThan(_: void, a: Shadow, b: Shadow) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    // find max name length for padding
    var max_name_len: usize = 0;
    for (shadows.items) |s| {
        if (s.name.len > max_name_len) max_name_len = s.name.len;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const w = &stdout_file_writer.interface;

    for (shadows.items) |v| {
        // right-align the name with padding
        const padding = max_name_len - v.name.len;
        for (0..padding) |_| {
            try w.writeAll(" ");
        }
        try w.writeAll(LIGHT_RED);
        try w.writeAll(v.name);
        try w.writeAll(RESET);
        try w.writeAll(" ");

        for (v.dirs, 0..) |dir_path, j| {
            if (j > 0) try w.writeAll(", ");
            try writeColoredPath(w, dir_path, home, prefixes);
        }
        try w.writeAll("\n");
    }

    try w.flush();
}

const CollectedPaths = struct {
    paths: std.ArrayList([]const u8),
    duplicates: std.ArrayList(bool),

    fn deinit(self: *CollectedPaths, gpa: std.mem.Allocator) void {
        self.paths.deinit(gpa);
        self.duplicates.deinit(gpa);
    }
};

fn collectPaths(gpa: std.mem.Allocator, path_env: []const u8, include_duplicates: bool) !CollectedPaths {
    var result: CollectedPaths = .{
        .paths = .empty,
        .duplicates = .empty,
    };
    var seen = std.StringHashMap(void).init(gpa);
    defer seen.deinit();

    var iter = std.mem.splitScalar(u8, path_env, ':');
    while (iter.next()) |dir_path| {
        if (dir_path.len == 0) continue;
        const gop = seen.getOrPut(dir_path) catch continue;
        if (gop.found_existing) {
            if (!include_duplicates) continue;
            try result.paths.append(gpa, dir_path);
            try result.duplicates.append(gpa, true);
        } else {
            try result.paths.append(gpa, dir_path);
            try result.duplicates.append(gpa, false);
        }
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    const env = init.environ_map;
    const home = env.get("HOME") orelse "";
    const path_env = env.get("PATH") orelse "";

    const io = init.io;
    const gpa = init.gpa;

    var interactive = false;
    var shadow = false;
    var show_duplicates = false;
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_iter.skip(); // skip program name

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i")) {
            interactive = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--shadow")) {
            shadow = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--duplicate")) {
            show_duplicates = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            var stdout_buf: [256]u8 = undefined;
            var stdout_w: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
            try stdout_w.interface.writeAll(PROGRAM_NAME ++ " " ++ build_options.version ++ "\n");
            try stdout_w.interface.flush();
            return;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            var buf: [512]u8 = undefined;
            var writer: Io.File.Writer = .init(.stdout(), io, &buf);
            try writer.interface.writeAll("usage: " ++ PROGRAM_NAME ++
                \\ [options]
                \\
                \\display PATH directories with colors and file counts
                \\
                \\options:
                \\  -i              interactive mode
                \\  -d, --duplicate show duplicate PATH entries
                \\  -s, --shadow    show executables found in multiple paths
                \\  -v, --version   print version
                \\  -h, --help      print this help
                \\
                \\config: ~/.paths.json
                \\  {"special_prefixes": ["/opt/homebrew", "/usr/local"]}
                \\
            );
            try writer.interface.flush();
            return;
        }
    }

    const prefixes: []const []const u8 = switch (loadConfig(gpa, home, io)) {
        .not_found => &default_special_prefixes,
        .err => return error.InvalidConfig,
        .ok => |p| p,
    };

    if (interactive) {
        var collected = try collectPaths(gpa, path_env, show_duplicates);
        defer collected.deinit(gpa);
        interactiveMode(collected.paths.items, collected.duplicates.items, home, io, prefixes);
        return;
    }

    if (shadow) {
        var collected = try collectPaths(gpa, path_env, false);
        defer collected.deinit(gpa);
        try shadowMode(gpa, collected.paths.items, home, io, prefixes);
        return;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    var seen = std.StringHashMap(void).init(gpa);
    defer seen.deinit();

    var iter = std.mem.splitScalar(u8, path_env, ':');
    while (iter.next()) |dir_path| {
        if (dir_path.len == 0) continue;
        const result = seen.getOrPut(dir_path) catch continue;
        if (result.found_existing) {
            if (!show_duplicates) continue;
            try printEntry(writer, io, dir_path, home, prefixes, true);
        } else {
            try printEntry(writer, io, dir_path, home, prefixes, false);
        }
    }

    try writer.flush();
}

test "findSpecialPrefix detects known prefixes" {
    const prefixes = &default_special_prefixes;
    try std.testing.expectEqual(@as(?usize, 13), findSpecialPrefix("/opt/homebrew/bin", prefixes));
    try std.testing.expectEqual(@as(?usize, 13), findSpecialPrefix("/opt/homebrew/sbin", prefixes));
    try std.testing.expectEqual(@as(?usize, 13), findSpecialPrefix("/opt/homebrew", prefixes));
    try std.testing.expectEqual(@as(?usize, 13), findSpecialPrefix("/opt/workbrew/bin", prefixes));
    try std.testing.expectEqual(@as(?usize, 13), findSpecialPrefix("/opt/zerobrew/prefix/bin", prefixes));
}

test "findSpecialPrefix rejects non-matching paths" {
    const prefixes = &default_special_prefixes;
    try std.testing.expectEqual(@as(?usize, null), findSpecialPrefix("/usr/bin", prefixes));
    try std.testing.expectEqual(@as(?usize, null), findSpecialPrefix("/opt/homebrewery", prefixes));
    try std.testing.expectEqual(@as(?usize, null), findSpecialPrefix("/opt/homebrew2/bin", prefixes));
    try std.testing.expectEqual(@as(?usize, null), findSpecialPrefix("", prefixes));
    try std.testing.expectEqual(@as(?usize, null), findSpecialPrefix("/opt/pmk/env/global/bin", prefixes));
}

test "shortenHome replaces home prefix with suffix" {
    const home = "/Users/test";
    {
        const r = shortenHome("/Users/test/bin", home);
        try std.testing.expect(r.is_home);
        try std.testing.expectEqualStrings("/bin", r.suffix);
    }
    {
        const r = shortenHome("/Users/test", home);
        try std.testing.expect(r.is_home);
        try std.testing.expectEqualStrings("", r.suffix);
    }
}

test "shortenHome does not match partial home" {
    const home = "/Users/test";
    {
        const r = shortenHome("/Users/testing/bin", home);
        try std.testing.expect(!r.is_home);
        try std.testing.expectEqualStrings("/Users/testing/bin", r.suffix);
    }
    {
        const r = shortenHome("/usr/bin", home);
        try std.testing.expect(!r.is_home);
        try std.testing.expectEqualStrings("/usr/bin", r.suffix);
    }
}
