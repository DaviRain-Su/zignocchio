const sdk = @import("sdk");

const EmptyAccounts = struct {};

fn initialize(_: sdk.Context(EmptyAccounts), _: []const u8) sdk.ProgramResult {
    return {};
}

const LowercaseOnlyProgram = struct {
    pub const instructions = .{
        .{
            .name = "initialize",
            .accounts = EmptyAccounts,
            .handler = initialize,
        },
    };
};

comptime {
    _ = sdk.framework.exportProgram(LowercaseOnlyProgram);
}
