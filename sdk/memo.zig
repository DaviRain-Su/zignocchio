//! SPL Memo Program CPI helpers
//!
//! The Memo Program allows programs to record text strings on-chain.
//! It is commonly used to attach human-readable messages or transaction
//! identifiers to instructions.
//!
//! Program ID: `MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr`

const sdk = @import("zignocchio.zig");

/// SPL Memo Program ID
/// MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr
pub fn getMemoProgramId(out: *sdk.Pubkey) void {
    out.* = .{
        0x05, 0x4a, 0x09, 0x77, 0x8e, 0x88, 0x6b, 0x4b,
        0x56, 0x99, 0x06, 0x02, 0x29, 0x31, 0x05, 0x4b,
        0x1b, 0x6a, 0x36, 0x15, 0xce, 0xfd, 0x31, 0x84,
        0x82, 0x7e, 0x79, 0x03, 0x6c, 0x7b, 0xde, 0x33,
    };
}

/// Add a memo to the transaction.
///
/// Accounts in `signers` are marked as signers in the CPI. Pass an empty
/// slice if the memo should be recorded without any signers.
///
/// The caller is responsible for ensuring all provided accounts are valid
/// signers (use `guard.assert_signer` when applicable).
pub fn addMemo(
    memo: []const u8,
    signers: []const sdk.AccountInfo,
) sdk.ProgramResult {
    var memo_program_id: sdk.Pubkey = undefined;
    getMemoProgramId(&memo_program_id);

    var account_metas: [16]sdk.AccountMeta = undefined;
    if (signers.len > account_metas.len) {
        return error.InvalidArgument;
    }

    for (signers, 0..) |signer, i| {
        account_metas[i] = .{
            .pubkey = signer.key(),
            .is_signer = true,
            .is_writable = false,
        };
    }

    const instruction = sdk.Instruction{
        .program_id = &memo_program_id,
        .accounts = account_metas[0..signers.len],
        .data = memo,
    };

    try sdk.invoke(&instruction, signers);
}

// =============================================================================
// Tests
// =============================================================================

test "getMemoProgramId returns correct bytes" {
    var id: sdk.Pubkey = undefined;
    getMemoProgramId(&id);
    const expected: sdk.Pubkey = .{
        0x05, 0x4a, 0x09, 0x77, 0x8e, 0x88, 0x6b, 0x4b,
        0x56, 0x99, 0x06, 0x02, 0x29, 0x31, 0x05, 0x4b,
        0x1b, 0x6a, 0x36, 0x15, 0xce, 0xfd, 0x31, 0x84,
        0x82, 0x7e, 0x79, 0x03, 0x6c, 0x7b, 0xde, 0x33,
    };
    try @import("std").testing.expectEqual(expected, id);
}
