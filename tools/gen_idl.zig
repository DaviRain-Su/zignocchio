const std = @import("std");
const sdk = @import("sdk");
const example = @import("example");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.debug.print("Usage: gen_idl <program-name> <output-path>\n", .{});
        return error.MissingProgramName;
    }
    if (args.len < 3) {
        std.debug.print("Usage: gen_idl <program-name> <output-path>\n", .{});
        return error.MissingOutputPath;
    }
    if (args.len > 3) {
        std.debug.print("Usage: gen_idl <program-name> <output-path>\n", .{});
        return error.TooManyArguments;
    }

    const program_name = args[1];
    const output_path = args[2];

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var writer: sdk.framework.IdlJsonArrayListWriter = .{
        .out = &output,
        .allocator = allocator,
    };

    try sdk.framework.writeIdlJson(example.Program, &writer, program_name);

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = output_path,
        .data = output.items,
    });
}
