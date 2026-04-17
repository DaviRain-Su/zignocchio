//! Associated Token Account (ATA) Program CPI wrappers
//!
//! These functions provide high-level Zig APIs for creating and closing
//! Associated Token Accounts via CPI.

const sdk = @import("../zignocchio.zig");

/// Associated Token Account Program ID
/// ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efjNsVGFAx4K
pub const ASSOCIATED_TOKEN_PROGRAM_ID: sdk.Pubkey = .{
    0x8c, 0x97, 0x25, 0x7f, 0x83, 0x49, 0x14, 0x86,
    0xfe, 0x3c, 0xef, 0xb2, 0xe7, 0x11, 0x61, 0xeb,
    0x11, 0x82, 0x3c, 0x20, 0x3d, 0x8c, 0x9a, 0x35,
    0x7f, 0xb6, 0xbf, 0xea, 0xda, 0x8e, 0xeb, 0xb8,
};

/// Write the Associated Token Account Program ID into the provided buffer.
/// Uses stack copy to avoid the Zig 0.16 BPF module-scope const address trap.
pub fn getAssociatedTokenProgramId(out: *sdk.Pubkey) void {
    out[0] = 0x8c;
    out[1] = 0x97;
    out[2] = 0x25;
    out[3] = 0x7f;
    out[4] = 0x83;
    out[5] = 0x49;
    out[6] = 0x14;
    out[7] = 0x86;
    out[8] = 0xfe;
    out[9] = 0x3c;
    out[10] = 0xef;
    out[11] = 0xb2;
    out[12] = 0xe7;
    out[13] = 0x11;
    out[14] = 0x61;
    out[15] = 0xeb;
    out[16] = 0x11;
    out[17] = 0x82;
    out[18] = 0x3c;
    out[19] = 0x20;
    out[20] = 0x3d;
    out[21] = 0x8c;
    out[22] = 0x9a;
    out[23] = 0x35;
    out[24] = 0x7f;
    out[25] = 0xb6;
    out[26] = 0xbf;
    out[27] = 0xea;
    out[28] = 0xda;
    out[29] = 0x8e;
    out[30] = 0xeb;
    out[31] = 0xb8;
}

/// Create an Associated Token Account via the ATA Program CPI.
///
/// Accounts:
/// - `payer`: signer, writable — pays for the new account creation
/// - `associated_token_account`: writable — the ATA address to be created
/// - `owner`: the wallet address that will own the ATA
/// - `mint`: the mint address for the token
/// - `system_program`: the System Program
/// - `token_program`: the SPL Token Program
pub fn createAssociatedTokenAccount(
    payer: sdk.AccountInfo,
    associated_token_account: sdk.AccountInfo,
    owner: sdk.AccountInfo,
    mint: sdk.AccountInfo,
    system_program: sdk.AccountInfo,
    token_program: sdk.AccountInfo,
) sdk.ProgramResult {
    var ata_program_id: sdk.Pubkey = undefined;
    getAssociatedTokenProgramId(&ata_program_id);

    const instruction_data = [_]u8{0}; // Create discriminator

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = payer.key(), .is_writable = true, .is_signer = true },
        .{ .pubkey = associated_token_account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = owner.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = mint.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = system_program.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = token_program.key(), .is_writable = false, .is_signer = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &ata_program_id,
        .accounts = &account_metas,
        .data = &instruction_data,
    };

    const accounts = [_]sdk.AccountInfo{
        payer,
        associated_token_account,
        owner,
        mint,
        system_program,
        token_program,
    };

    try sdk.invoke(&instruction, &accounts);
}

// =============================================================================
// Tests
// =============================================================================

const std = @import("std");

test "getAssociatedTokenProgramId returns ATA program id" {
    var id: sdk.Pubkey = undefined;
    getAssociatedTokenProgramId(&id);

    const expected: sdk.Pubkey = .{
        0x8c, 0x97, 0x25, 0x7f, 0x83, 0x49, 0x14, 0x86,
        0xfe, 0x3c, 0xef, 0xb2, 0xe7, 0x11, 0x61, 0xeb,
        0x11, 0x82, 0x3c, 0x20, 0x3d, 0x8c, 0x9a, 0x35,
        0x7f, 0xb6, 0xbf, 0xea, 0xda, 0x8e, 0xeb, 0xb8,
    };
    try std.testing.expectEqual(expected, id);
}

test "ASSOCIATED_TOKEN_PROGRAM_ID constant matches expected" {
    const expected: sdk.Pubkey = .{
        0x8c, 0x97, 0x25, 0x7f, 0x83, 0x49, 0x14, 0x86,
        0xfe, 0x3c, 0xef, 0xb2, 0xe7, 0x11, 0x61, 0xeb,
        0x11, 0x82, 0x3c, 0x20, 0x3d, 0x8c, 0x9a, 0x35,
        0x7f, 0xb6, 0xbf, 0xea, 0xda, 0x8e, 0xeb, 0xb8,
    };
    try std.testing.expectEqual(expected, ASSOCIATED_TOKEN_PROGRAM_ID);
}

/// Create an Associated Token Account idempotently via the ATA Program CPI.
/// If the account already exists, the instruction succeeds without changes.
pub fn createAssociatedTokenAccountIdempotent(
    payer: sdk.AccountInfo,
    associated_token_account: sdk.AccountInfo,
    owner: sdk.AccountInfo,
    mint: sdk.AccountInfo,
    system_program: sdk.AccountInfo,
    token_program: sdk.AccountInfo,
) sdk.ProgramResult {
    var ata_program_id: sdk.Pubkey = undefined;
    getAssociatedTokenProgramId(&ata_program_id);

    const instruction_data = [_]u8{1}; // CreateIdempotent discriminator

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = payer.key(), .is_writable = true, .is_signer = true },
        .{ .pubkey = associated_token_account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = owner.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = mint.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = system_program.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = token_program.key(), .is_writable = false, .is_signer = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &ata_program_id,
        .accounts = &account_metas,
        .data = &instruction_data,
    };

    const accounts = [_]sdk.AccountInfo{
        payer,
        associated_token_account,
        owner,
        mint,
        system_program,
        token_program,
    };

    try sdk.invoke(&instruction, &accounts);
}

/// Close a token account (commonly used to close an ATA).
/// This is a convenience wrapper around the SPL Token Program's CloseAccount instruction.
///
/// Accounts:
/// - `account`: writable — the token account to close
/// - `destination`: writable — receives the remaining lamports
/// - `authority`: signer — owner or close authority of the token account
pub fn closeAssociatedTokenAccount(
    account: sdk.AccountInfo,
    destination: sdk.AccountInfo,
    authority: sdk.AccountInfo,
) sdk.ProgramResult {
    var token_program_id: sdk.Pubkey = undefined;
    sdk.token.getTokenProgramId(&token_program_id);

    const instruction_data = [_]u8{9}; // CloseAccount discriminator

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_program_id,
        .accounts = &account_metas,
        .data = &instruction_data,
    };

    const accounts = [_]sdk.AccountInfo{ account, destination, authority };
    try sdk.invoke(&instruction, &accounts);
}
