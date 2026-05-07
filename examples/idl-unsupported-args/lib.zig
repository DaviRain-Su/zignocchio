//! Negative IDL fixture: instruction args are intentionally unsupported.

const sdk = @import("sdk");

const EmptyAccounts = struct {};

pub const Program = struct {
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

fn takesArgs(
    _: sdk.Context(EmptyAccounts),
    _: []const u8,
) sdk.ProgramResult {
    return {};
}
