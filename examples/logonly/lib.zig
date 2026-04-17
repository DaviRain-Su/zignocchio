//! LogOnly - Program that only calls sol_log_ for debugging litesvm compatibility

const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(1, processInstruction), .{input});
}

fn processInstruction(
    _: *const sdk.Pubkey,
    _: []sdk.AccountInfo,
    _: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("logonly: hello");
    return {};
}
