const sdk = @import("sdk");

const EmptyAccounts = struct {};

fn takesArgs(_: sdk.Context(EmptyAccounts), _: []const u8) sdk.ProgramResult {
    return {};
}

const ProgramWithArgs = struct {
    pub const Instruction = .{
        .{
            .name = "takes_args",
            .accounts = EmptyAccounts,
            .handler = takesArgs,
            .args = .{
                .{
                    .name = "amount",
                    .type = "u64",
                },
            },
        },
    };
};

const CompileOnlyWriter = struct {
    pub fn writeAll(_: @This(), _: []const u8) !void {}
    pub fn writeByte(_: @This(), _: u8) !void {}
    pub fn print(_: @This(), comptime _: []const u8, _: anytype) !void {}
};

comptime {
    var writer = CompileOnlyWriter{};
    sdk.framework.writeIdlJson(ProgramWithArgs, writer, "idl-args") catch unreachable;
}
