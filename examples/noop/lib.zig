//! NOOP - Minimal program for debugging litesvm compatibility
//!
//! This program does absolutely nothing (no syscalls, no logs, no CPI).
//! It is used to isolate whether litesvm's execution error comes from:
//! 1. Entrypoint / input-buffer parsing, or
//! 2. Syscall ABI mismatches (e.g. sol_log_).

const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(1, processInstruction), .{input});
}

fn processInstruction(
    _: *const sdk.Pubkey,
    _: []sdk.AccountInfo,
    _: []const u8,
) sdk.ProgramResult {
    // Absolutely nothing. No logs, no syscalls.
    return {};
}
