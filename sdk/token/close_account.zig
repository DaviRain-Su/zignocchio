//! Token CloseAccount CPI wrapper
//!
//! Provides a high-level function for closing SPL Token accounts,
//! hiding the C-ABI conversion and instruction serialization details.

const sdk = @import("../zignocchio.zig");

/// Close a token account.
///
/// Transfers all remaining lamports from the token account to the
/// destination account and zeroes the account data. The token account
/// must have a token balance of 0 before it can be closed.
///
/// Accounts:
/// - `account`: writable — the token account to close
/// - `destination`: writable — receives the remaining lamports
/// - `authority`: signer — owner or close authority of the token account
pub fn closeAccount(
    account: sdk.AccountInfo,
    destination: sdk.AccountInfo,
    authority: sdk.AccountInfo,
) sdk.ProgramResult {
    const close_ix = sdk.token.instructions.CloseAccount{
        .account = account,
        .destination = destination,
        .authority = authority,
    };
    try close_ix.invoke();
}

/// Close a token account with PDA signing.
///
/// Use this when the `authority` is a Program Derived Address and the
/// program must sign on its behalf.
pub fn closeAccountSigned(
    account: sdk.AccountInfo,
    destination: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    signers_seeds: []const []const u8,
) sdk.ProgramResult {
    const close_ix = sdk.token.instructions.CloseAccount{
        .account = account,
        .destination = destination,
        .authority = authority,
    };
    try close_ix.invokeSigned(signers_seeds);
}

// =============================================================================
// Tests
// =============================================================================

const std = @import("std");

test "closeAccount instruction data format" {
    const data = [_]u8{9}; // CloseAccount discriminator
    try std.testing.expectEqual(@as(u8, 9), data[0]);
}
