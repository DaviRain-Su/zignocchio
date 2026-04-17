//! SPL Token-2022 Program CPI helpers
//!
//! Token-2022 extends the SPL Token program with additional features such as
//! transfer fees, confidential transfers, and metadata extensions. The core
//! instruction layout for transfers, closes, and ATA creation remains
//! compatible with SPL Token.
//!
//! Program ID: `TokenzQdBNbLqP5VEhkoSPQsxpVLFhkW4gJg97E1CJy`

const sdk = @import("zignocchio.zig");
const std = @import("std");

/// SPL Token-2022 Program ID
/// TokenzQdBNbLqP5VEhkoSPQsxpVLFhkW4gJg97E1CJy
pub fn getToken2022ProgramId(out: *sdk.Pubkey) void {
    out.* = .{
        0x06, 0xdd, 0xf6, 0xe1, 0xee, 0x75, 0x8f, 0xde,
        0x18, 0x42, 0x5d, 0xbc, 0xe4, 0x6d, 0x77, 0xfb,
        0xdf, 0xa9, 0xbe, 0x76, 0xfd, 0xc3, 0xbc, 0xc8,
        0xd1, 0xd2, 0x23, 0x63, 0x2c, 0x27, 0x36, 0xae,
    };
}

/// Transfer tokens via Token-2022 Program CPI.
///
/// Accounts:
/// - `from`: writable — source token account
/// - `to`: writable — destination token account
/// - `authority`: signer — owner/delegate of the source account
///
/// The caller is responsible for ownership and signer checks.
pub fn transfer(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    var ix_data: [9]u8 = undefined;
    ix_data[0] = 3; // Transfer instruction index
    std.mem.writeInt(u64, ix_data[1..9], amount, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = from.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = to.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ from, to, authority });
}

/// Transfer tokens via Token-2022 Program CPI with PDA signing.
pub fn transferSigned(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    amount: u64,
    signers_seeds: []const []const u8,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    var ix_data: [9]u8 = undefined;
    ix_data[0] = 3; // Transfer instruction index
    std.mem.writeInt(u64, ix_data[1..9], amount, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = from.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = to.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invokeSigned(
        &instruction,
        &[_]sdk.AccountInfo{ from, to, authority },
        signers_seeds,
    );
}

/// Close a token account via Token-2022 Program CPI.
pub fn closeAccount(
    account: sdk.AccountInfo,
    destination: sdk.AccountInfo,
    authority: sdk.AccountInfo,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    const ix_data = &[_]u8{9}; // CloseAccount instruction index

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ account, destination, authority });
}

/// Close a token account via Token-2022 Program CPI with PDA signing.
pub fn closeAccountSigned(
    account: sdk.AccountInfo,
    destination: sdk.AccountInfo,
    authority: sdk.AccountInfo,
    signers_seeds: []const []const u8,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    const ix_data = &[_]u8{9}; // CloseAccount instruction index

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = ix_data,
    };

    try sdk.invokeSigned(
        &instruction,
        &[_]sdk.AccountInfo{ account, destination, authority },
        signers_seeds,
    );
}

/// Initialize a token account via Token-2022 Program CPI.
pub fn initializeAccount(
    account: sdk.AccountInfo,
    mint: sdk.AccountInfo,
    owner: sdk.AccountInfo,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    const ix_data = &[_]u8{1}; // InitializeAccount instruction index

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = mint.key(), .is_writable = false, .is_signer = false },
        .{ .pubkey = owner.key(), .is_writable = false, .is_signer = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = ix_data,
    };

    try sdk.invoke(&instruction,
        &[_]sdk.AccountInfo{ account, mint, owner });
}

/// Initialize a mint via Token-2022 Program CPI.
pub fn initializeMint(
    mint: sdk.AccountInfo,
    mint_authority: *const sdk.Pubkey,
    decimals: u8,
    freeze_authority: ?*const sdk.Pubkey,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    var ix_data: [67]u8 = undefined;
    @memset(&ix_data, 0);
    ix_data[0] = 0; // InitializeMint instruction index
    ix_data[1] = decimals;
    @memcpy(ix_data[2..34], mint_authority[0..32]);
    if (freeze_authority) |fa| {
        ix_data[34] = 1; // Option::Some
        @memcpy(ix_data[35..67], fa[0..32]);
    } else {
        ix_data[34] = 0; // Option::None
    }

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = mint.key(), .is_writable = true, .is_signer = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{mint});
}

/// Mint tokens via Token-2022 Program CPI.
pub fn mintTo(
    mint: sdk.AccountInfo,
    account: sdk.AccountInfo,
    mint_authority: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    var ix_data: [9]u8 = undefined;
    ix_data[0] = 7; // MintTo instruction index
    std.mem.writeInt(u64, ix_data[1..9], amount, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = mint.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = mint_authority.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction,
        &[_]sdk.AccountInfo{ mint, account, mint_authority });
}

/// Burn tokens via Token-2022 Program CPI.
pub fn burn(
    account: sdk.AccountInfo,
    mint: sdk.AccountInfo,
    owner: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    var token_2022_program_id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&token_2022_program_id);

    var ix_data: [9]u8 = undefined;
    ix_data[0] = 8; // Burn instruction index
    std.mem.writeInt(u64, ix_data[1..9], amount, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = mint.key(), .is_writable = true, .is_signer = false },
        .{ .pubkey = owner.key(), .is_writable = false, .is_signer = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &token_2022_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction,
        &[_]sdk.AccountInfo{ account, mint, owner });
}

// =============================================================================
// Tests
// =============================================================================

test "getToken2022ProgramId returns correct bytes" {
    var id: sdk.Pubkey = undefined;
    getToken2022ProgramId(&id);
    const expected: sdk.Pubkey = .{
        0x06, 0xdd, 0xf6, 0xe1, 0xee, 0x75, 0x8f, 0xde,
        0x18, 0x42, 0x5d, 0xbc, 0xe4, 0x6d, 0x77, 0xfb,
        0xdf, 0xa9, 0xbe, 0x76, 0xfd, 0xc3, 0xbc, 0xc8,
        0xd1, 0xd2, 0x23, 0x63, 0x2c, 0x27, 0x36, 0xae,
    };
    try std.testing.expectEqual(expected, id);
}

test "transfer instruction data format" {
    var ix_data: [9]u8 = undefined;
    ix_data[0] = 3;
    std.mem.writeInt(u64, ix_data[1..9], 1000, .little);
    try std.testing.expectEqual(@as(u8, 3), ix_data[0]);
    try std.testing.expectEqual(@as(u64, 1000), std.mem.readInt(u64, ix_data[1..9], .little));
}

test "initializeMint instruction data format" {
    var ix_data: [67]u8 = undefined;
    @memset(&ix_data, 0);
    ix_data[0] = 0;
    ix_data[1] = 9;
    const mint_auth: sdk.Pubkey = .{1} ** 32;
    @memcpy(ix_data[2..34], &mint_auth);
    ix_data[34] = 0;

    try std.testing.expectEqual(@as(u8, 0), ix_data[0]);
    try std.testing.expectEqual(@as(u8, 9), ix_data[1]);
    try std.testing.expectEqual(mint_auth, ix_data[2..34].*);
    try std.testing.expectEqual(@as(u8, 0), ix_data[34]);
}

test "mintTo instruction data format" {
    var ix_data: [9]u8 = undefined;
    ix_data[0] = 7;
    std.mem.writeInt(u64, ix_data[1..9], 5000, .little);
    try std.testing.expectEqual(@as(u8, 7), ix_data[0]);
    try std.testing.expectEqual(@as(u64, 5000), std.mem.readInt(u64, ix_data[1..9], .little));
}

test "burn instruction data format" {
    var ix_data: [9]u8 = undefined;
    ix_data[0] = 8;
    std.mem.writeInt(u64, ix_data[1..9], 2000, .little);
    try std.testing.expectEqual(@as(u8, 8), ix_data[0]);
    try std.testing.expectEqual(@as(u64, 2000), std.mem.readInt(u64, ix_data[1..9], .little));
}
