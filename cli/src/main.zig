//! zignocchio-cli entrypoint
//!
//! Usage: zignocchio-cli new <name> [--path <dir>]

const std = @import("std");
const commands = @import("commands.zig");

pub fn main(process: std.process.Init) !void {
    const allocator = process.gpa;
    var arg_it = try std.process.Args.Iterator.initAllocator(process.minimal.args, allocator);
    defer arg_it.deinit();

    _ = arg_it.skip(); // skip executable name
    const cmd = arg_it.next() orelse {
        std.log.info("zignocchio-cli", .{});
        std.log.info("Usage: zignocchio-cli new <name> [--path <dir>]", .{});
        return;
    };

    if (std.mem.eql(u8, cmd, "new")) {
        var arg_list: std.ArrayList([]const u8) = .empty;
        defer arg_list.deinit(allocator);
        while (arg_it.next()) |arg| {
            try arg_list.append(allocator, arg);
        }
        try commands.execNew(allocator, arg_list.items);
    } else {
        std.log.err("Unknown command: {s}", .{cmd});
        std.log.err("Usage: zignocchio-cli new <name> [--path <dir>]", .{});
        return error.UnknownCommand;
    }
}
