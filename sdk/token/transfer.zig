//! Token Transfer CPI wrapper
//!
//! Provides a high-level function for SPL Token transfers, hiding the
//! C-ABI conversion and instruction serialization details.

const sdk = @import("../zignocchio.zig");

/// Transfer tokens from one token account to another.
///
/// Accounts:
/// - `from`: writable — source token account
/// - `to`: writable — destination token account
/// - `authority`: signer — owner or delegate of the source account
///
/// The caller is responsible for ensuring the authority is valid.
pub fn transfer(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    const transfer_ix = sdk.token.instructions.Transfer{
        .from = from,
        .to = to,
        .authority = authority,
        .amount = amount,
    };
    try transfer_ix.invoke();
}

/// Transfer tokens with PDA signing.
///
/// Use this when the `authority` is a Program Derived Address and the
/// program must sign on its behalf.
pub fn transferSigned(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    amount: u64,
    signers_seeds: []const []const u8,
) sdk.ProgramResult {
    const transfer_ix = sdk.token.instructions.Transfer{
        .from = from,
        .to = to,
        .authority = authority,
        .amount = amount,
    };
    try transfer_ix.invokeSigned(signers_seeds);
}

// =============================================================================
// Tests
// =============================================================================

const std = @import("std");

test "transfer instruction data format" {
    // Verify the expected instruction data layout manually
    var data: [9]u8 = undefined;
    data[0] = 3; // Transfer discriminator
    std.mem.writeInt(u64, data[1..9], 1000, .little);

    try std.testing.expectEqual(@as(u8, 3), data[0]);
    try std.testing.expectEqual(@as(u64, 1000), std.mem.readInt(u64, data[1..9], .little));
}
