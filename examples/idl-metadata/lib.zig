//! IDL metadata fixture with multiple framework instructions and account shapes.

const sdk = @import("sdk");

const MetadataAccounts = struct {
    authority: sdk.Signer,
    writable_vault: sdk.WritableAccount,
    readonly_config: sdk.ReadonlyAccount,
    token_program: sdk.ProgramAccount,
    raw_escape: sdk.AccountInfo,
};

const EmptyAccounts = struct {};

pub const Program = struct {
    pub const max_accounts = 5;

    pub const Instruction = .{
        .{
            .name = "initialize_metadata",
            .accounts = MetadataAccounts,
            .handler = initializeMetadata,
        },
        .{
            .name = "refresh_metadata",
            .accounts = EmptyAccounts,
            .handler = refreshMetadata,
        },
        .{
            .name = "close_metadata",
            .accounts = EmptyAccounts,
            .handler = closeMetadata,
        },
    };
};

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.exportProgram(Program), .{input});
}

fn initializeMetadata(
    ctx: sdk.Context(MetadataAccounts),
    _: []const u8,
) sdk.ProgramResult {
    try validateMetadataAccounts(ctx);
    return {};
}

fn refreshMetadata(
    _: sdk.Context(EmptyAccounts),
    _: []const u8,
) sdk.ProgramResult {
    return {};
}

fn closeMetadata(
    _: sdk.Context(EmptyAccounts),
    _: []const u8,
) sdk.ProgramResult {
    return {};
}

fn validateMetadataAccounts(ctx: sdk.Context(MetadataAccounts)) sdk.ProgramResult {
    const accounts = ctx.accounts;
    if (!accounts.authority.isSigner()) return error.MissingRequiredSignature;
    if (!accounts.writable_vault.isWritable()) return error.ImmutableAccount;
    if (accounts.readonly_config.isWritable()) return error.ImmutableAccount;
    if (!accounts.token_program.executable()) return error.InvalidArgument;
    if (accounts.raw_escape.isSigner() or accounts.raw_escape.isWritable() or accounts.raw_escape.executable()) {
        return error.InvalidArgument;
    }
    return {};
}
