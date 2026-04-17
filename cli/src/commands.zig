//! CLI command implementations using C stdlib for simplicity.

const std = @import("std");
const template = @import("template.zig");

extern "c" fn system([*:0]const u8) c_int;
extern "c" fn access([*:0]const u8, mode: c_int) c_int;

fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const file = std.c.fopen(path_z.ptr, "w") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(file);

    const written = std.c.fwrite(content.ptr, 1, content.len, file);
    if (written != content.len) return error.FileWriteFailed;
}

fn runShell(allocator: std.mem.Allocator, cmd: []const u8) !void {
    const cmd_z = try allocator.dupeZ(u8, cmd);
    defer allocator.free(cmd_z);
    const result = system(cmd_z.ptr);
    if (result != 0) return error.CommandFailed;
}

/// Replace all occurrences of `needle` with `replacement` in `haystack`.
fn replaceAll(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, haystack);

    var count: usize = 0;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            count += 1;
            i += needle.len;
        } else {
            i += 1;
        }
    }

    const new_len = haystack.len + count * (replacement.len - needle.len);
    var result = try allocator.alloc(u8, new_len);
    errdefer allocator.free(result);

    var src: usize = 0;
    var dst: usize = 0;
    while (src <= haystack.len - needle.len) {
        if (std.mem.eql(u8, haystack[src .. src + needle.len], needle)) {
            @memcpy(result[dst .. dst + replacement.len], replacement);
            dst += replacement.len;
            src += needle.len;
        } else {
            result[dst] = haystack[src];
            dst += 1;
            src += 1;
        }
    }
    while (src < haystack.len) {
        result[dst] = haystack[src];
        dst += 1;
        src += 1;
    }

    return result;
}

pub fn execNew(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: zignocchio-cli new <name> [--path <dir>]", .{});
        return error.InvalidArguments;
    }

    const name = args[0];
    var output_dir: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--path") and i + 1 < args.len) {
            output_dir = args[i + 1];
            i += 1;
        }
    }

    const project_path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(project_path);

    // Create project directory
    const mkdir_cmd = try std.fmt.allocPrint(allocator, "mkdir -p {s}", .{project_path});
    defer allocator.free(mkdir_cmd);
    try runShell(allocator, mkdir_cmd);

    // Write build.zig
    const build_zig_path = try std.fs.path.join(allocator, &.{ project_path, "build.zig" });
    defer allocator.free(build_zig_path);
    try writeFile(allocator, build_zig_path, template.build_zig);

    // Write src/lib.zig
    const src_dir = try std.fs.path.join(allocator, &.{ project_path, "src" });
    defer allocator.free(src_dir);
    const mkdir_src_cmd = try std.fmt.allocPrint(allocator, "mkdir -p {s}", .{src_dir});
    defer allocator.free(mkdir_src_cmd);
    try runShell(allocator, mkdir_src_cmd);

    const lib_zig_content = try replaceAll(allocator, template.lib_zig, "%%NAME%%", name);
    defer allocator.free(lib_zig_content);
    const lib_zig_path = try std.fs.path.join(allocator, &.{ src_dir, "lib.zig" });
    defer allocator.free(lib_zig_path);
    try writeFile(allocator, lib_zig_path, lib_zig_content);

    // Write tests/program.test.ts
    const tests_dir = try std.fs.path.join(allocator, &.{ project_path, "tests" });
    defer allocator.free(tests_dir);
    const mkdir_tests_cmd = try std.fmt.allocPrint(allocator, "mkdir -p {s}", .{tests_dir});
    defer allocator.free(mkdir_tests_cmd);
    try runShell(allocator, mkdir_tests_cmd);

    const test_ts_content = try replaceAll(allocator, template.test_ts, "%%NAME%%", name);
    defer allocator.free(test_ts_content);
    const test_ts_path = try std.fs.path.join(allocator, &.{ tests_dir, "program.test.ts" });
    defer allocator.free(test_ts_path);
    try writeFile(allocator, test_ts_path, test_ts_content);

    // Copy sdk directory from current working directory or parent (when CLI is in cli/)
    const sdk_src: []const u8 = if (access("sdk", 0) == 0) "sdk" else "../sdk";
    const cp_cmd = try std.fmt.allocPrint(allocator, "cp -r {s} {s}/sdk", .{ sdk_src, project_path });
    defer allocator.free(cp_cmd);
    try runShell(allocator, cp_cmd);

    std.log.info("Created project: {s}", .{project_path});
    std.log.info("To get started:", .{});
    std.log.info("  cd {s}", .{project_path});
    std.log.info("  zig build", .{});
    std.log.info("  npx jest tests/program.test.ts", .{});
}

// =============================================================================
// Tests
// =============================================================================

test "replaceAll replaces all occurrences" {
    const allocator = std.testing.allocator;
    const result = try replaceAll(allocator, "hello %%NAME%% and %%NAME%%", "%%NAME%%", "world");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world and world", result);
}

test "replaceAll returns copy when needle not found" {
    const allocator = std.testing.allocator;
    const result = try replaceAll(allocator, "hello world", "%%NAME%%", "foo");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "replaceAll handles empty needle" {
    const allocator = std.testing.allocator;
    const result = try replaceAll(allocator, "hello", "", "foo");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}
