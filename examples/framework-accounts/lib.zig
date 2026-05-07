//! Minimal framework account reflection runtime fixture.

const sdk = @import("sdk");

const Accounts = struct {
    signer: sdk.framework.Signer,
    writable: sdk.framework.WritableAccount,
    readonly: sdk.framework.ReadonlyAccount,
    program: sdk.framework.ProgramAccount,
    raw: sdk.AccountInfo,
};

const Program = struct {
    pub const max_accounts = 5;

    pub const Instruction = .{
        .{
            .name = "touch_accounts",
            .accounts = Accounts,
            .handler = touchAccounts,
        },
    };
};

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.exportProgram(Program), .{input});
}

fn touchAccounts(
    ctx: sdk.Context(Accounts),
    _: []const u8,
) sdk.ProgramResult {
    const accounts = ctx.accounts;

    if (!accounts.signer.isSigner()) return error.MissingRequiredSignature;
    if (!accounts.writable.isWritable()) return error.ImmutableAccount;
    if (accounts.readonly.isWritable()) return error.ImmutableAccount;
    if (!accounts.program.executable()) return error.InvalidArgument;
    if (accounts.raw.isSigner() or accounts.raw.isWritable() or accounts.raw.executable()) {
        return error.InvalidArgument;
    }

    if (accounts.readonly.dataLen() == 0 or accounts.raw.dataLen() == 0) {
        return error.AccountDataTooSmall;
    }

    var writable_data = try accounts.writable.tryBorrowMutData();
    defer writable_data.release();

    if (writable_data.value.len < 5) {
        return error.AccountDataTooSmall;
    }

    writable_data.value[0] = 0xa5;
    writable_data.value[1] = if (!accounts.readonly.isWritable()) 0x42 else 0;
    writable_data.value[2] = accounts.raw.dataPtr()[0];
    writable_data.value[3] = if (accounts.signer.isSigner()) 1 else 0;
    writable_data.value[4] = if (accounts.program.executable()) 1 else 0;
}
