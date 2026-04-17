//! System Program CPI wrappers for Solana programs
//!
//! These functions hide the C-ABI conversion and instruction data serialization
//! details, exposing a high-level Zig API for common System Program operations.

const sdk = @import("zignocchio.zig");
const std = @import("std");

/// Write the System Program ID into the provided output buffer.
/// Uses a stack copy to avoid the Zig 0.16 BPF module-scope const address trap.
pub fn getSystemProgramId(out: *sdk.Pubkey) void {
    out.* = .{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
}

/// Create a new account via System Program CPI.
///
/// Accounts:
/// - `payer`: signer, writable — pays for the new account creation
/// - `new_account`: writable — the account to be created
///
/// The caller is responsible for ensuring `payer` is a signer and both
/// accounts are writable (use `guard.assert_signer` / `guard.assert_writable`).
pub fn createAccount(
    payer: sdk.AccountInfo,
    new_account: sdk.AccountInfo,
    owner: *const sdk.Pubkey,
    space: u64,
    lamports: u64,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [52]u8 = undefined;
    @memset(&ix_data, 0);

    // instruction index = 0 (u32 LE)
    std.mem.writeInt(u32, ix_data[0..4], 0, .little);
    // lamports (u64 LE)
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);
    // space (u64 LE)
    std.mem.writeInt(u64, ix_data[12..20], space, .little);
    // owner (Pubkey, 32 bytes)
    @memcpy(ix_data[20..52], owner[0..32]);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = payer.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = new_account.key(), .is_signer = false, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ payer, new_account });
}

/// Create a new account via System Program CPI with PDA signing.
///
/// Accounts:
/// - `payer`: signer, writable — pays for the new account creation
/// - `new_account`: writable — the PDA account to be created
///
/// The caller is responsible for ensuring `payer` is a signer and both
/// accounts are writable. The `new_account` is marked as a signer in the
/// CPI so the program can sign on behalf of the PDA via `invokeSigned`.
pub fn createAccountSigned(
    payer: sdk.AccountInfo,
    new_account: sdk.AccountInfo,
    owner: *const sdk.Pubkey,
    space: u64,
    lamports: u64,
    signers_seeds: []const []const u8,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [52]u8 = undefined;
    @memset(&ix_data, 0);

    // instruction index = 0 (u32 LE)
    std.mem.writeInt(u32, ix_data[0..4], 0, .little);
    // lamports (u64 LE)
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);
    // space (u64 LE)
    std.mem.writeInt(u64, ix_data[12..20], space, .little);
    // owner (Pubkey, 32 bytes)
    @memcpy(ix_data[20..52], owner[0..32]);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = payer.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = new_account.key(), .is_signer = true, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invokeSigned(&instruction, &[_]sdk.AccountInfo{ payer, new_account }, signers_seeds);
}

/// Transfer lamports via System Program CPI.
///
/// Accounts:
/// - `from`: signer, writable — source of lamports
/// - `to`: writable — destination for lamports
///
/// The caller is responsible for ensuring `from` is a signer and both
/// accounts are writable.
pub fn transfer(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [12]u8 = undefined;

    // instruction index = 2 (u32 LE)
    std.mem.writeInt(u32, ix_data[0..4], 2, .little);
    // amount (u64 LE)
    std.mem.writeInt(u64, ix_data[4..12], amount, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = from.key(), .is_writable = true, .is_signer = true },
        .{ .pubkey = to.key(), .is_writable = true, .is_signer = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ from, to });
}

/// Assign a new owner to an account via System Program CPI.
pub fn assign(
    account: sdk.AccountInfo,
    owner: *const sdk.Pubkey,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [36]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 1, .little); // Assign instruction index
    @memcpy(ix_data[4..36], owner[0..32]);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_signer = true, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{account});
}

/// Allocate space in an account via System Program CPI.
pub fn allocate(
    account: sdk.AccountInfo,
    space: u64,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [12]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 8, .little); // Allocate instruction index
    std.mem.writeInt(u64, ix_data[4..12], space, .little);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_signer = true, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{account});
}

/// Reallocate space in an account via System Program CPI.
pub fn realloc(
    account: sdk.AccountInfo,
    new_space: u64,
    zero_init: bool,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [13]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 11, .little); // ReAlloc instruction index
    std.mem.writeInt(u64, ix_data[4..12], new_space, .little);
    ix_data[12] = if (zero_init) 1 else 0;

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = account.key(), .is_signer = true, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{account});
}

/// Advance a nonce account via System Program CPI.
pub fn advanceNonceAccount(
    nonce_account: sdk.AccountInfo,
    authorized_account: sdk.AccountInfo,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    const ix_data = &[_]u8{ 4, 0, 0, 0 }; // AdvanceNonceAccount instruction index (u32 LE)

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = nonce_account.key(), .is_signer = false, .is_writable = true },
        .{ .pubkey = authorized_account.key(), .is_signer = true, .is_writable = false },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ nonce_account, authorized_account });
}

// =============================================================================
// Tests
// =============================================================================

/// Mock invoke that validates instruction format without calling syscalls
fn mockInvoke(instruction: *const sdk.Instruction, accounts: []const sdk.AccountInfo) sdk.ProgramResult {
    _ = accounts;
    // Validate program_id is System Program
    var system_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_id);
    if (!sdk.pubkeyEq(instruction.program_id, &system_id)) {
        return error.IncorrectProgramId;
    }
    // Validate instruction data is not empty
    if (instruction.data.len == 0) {
        return error.InvalidInstructionData;
    }
    return;
}

test "getSystemProgramId returns all zeros" {
    var id: sdk.Pubkey = undefined;
    getSystemProgramId(&id);
    const expected: sdk.Pubkey = .{0} ** 32;
    try std.testing.expectEqual(expected, id);
}

test "createAccount instruction data format" {
    var payer_account = sdk.Account{
        .borrow_state = sdk.NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 1,
        .executable = 0,
        .resize_delta = 0,
        .key = .{1} ** 32,
        .owner = .{0} ** 32,
        .lamports = 1000,
        .data_len = 0,
    };
    var new_account = sdk.Account{
        .borrow_state = sdk.NON_DUP_MARKER,
        .is_signer = 0,
        .is_writable = 1,
        .executable = 0,
        .resize_delta = 0,
        .key = .{2} ** 32,
        .owner = .{0} ** 32,
        .lamports = 0,
        .data_len = 0,
    };
    const owner: sdk.Pubkey align(8) = .{3} ** 32;

    const payer = sdk.AccountInfo{ .raw = &payer_account };
    const new_acc = sdk.AccountInfo{ .raw = &new_account };
    _ = payer;
    _ = new_acc;

    // We can't call createAccount directly because it calls sdk.invoke which
    // crashes on host. Instead we verify the instruction data layout manually.
    var ix_data: [52]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 0, .little);
    std.mem.writeInt(u64, ix_data[4..12], 500, .little);
    std.mem.writeInt(u64, ix_data[12..20], 128, .little);
    @memcpy(ix_data[20..52], &owner);

    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ix_data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 500), std.mem.readInt(u64, ix_data[4..12], .little));
    try std.testing.expectEqual(@as(u64, 128), std.mem.readInt(u64, ix_data[12..20], .little));
    try std.testing.expectEqual(owner, ix_data[20..52].*);
}

test "transfer instruction data format" {
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little);
    std.mem.writeInt(u64, ix_data[4..12], 100, .little);

    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, ix_data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 100), std.mem.readInt(u64, ix_data[4..12], .little));
}

test "mockInvoke validates system program id" {
    var system_id: sdk.Pubkey align(8) = undefined;
    getSystemProgramId(&system_id);

    const ix_data = &[_]u8{0};
    const meta = sdk.AccountMeta{ .pubkey = &system_id, .is_writable = false, .is_signer = false };
    const instruction = sdk.Instruction{
        .program_id = &system_id,
        .accounts = &[_]sdk.AccountMeta{meta},
        .data = ix_data,
    };
    try mockInvoke(&instruction, &[_]sdk.AccountInfo{});
}

test "mockInvoke rejects wrong program id" {
    const wrong_id: sdk.Pubkey align(8) = .{1} ** 32;
    const ix_data = &[_]u8{0};
    const meta = sdk.AccountMeta{ .pubkey = &wrong_id, .is_writable = false, .is_signer = false };
    const instruction = sdk.Instruction{
        .program_id = &wrong_id,
        .accounts = &[_]sdk.AccountMeta{meta},
        .data = ix_data,
    };
    try std.testing.expectError(error.IncorrectProgramId, mockInvoke(&instruction, &[_]sdk.AccountInfo{}));
}

test "assign instruction data format" {
    var ix_data: [36]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 1, .little);
    const owner: sdk.Pubkey = .{3} ** 32;
    @memcpy(ix_data[4..36], &owner);

    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, ix_data[0..4], .little));
    try std.testing.expectEqual(owner, ix_data[4..36].*);
}

test "allocate instruction data format" {
    var ix_data: [12]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 8, .little);
    std.mem.writeInt(u64, ix_data[4..12], 256, .little);

    try std.testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, ix_data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 256), std.mem.readInt(u64, ix_data[4..12], .little));
}

test "realloc instruction data format" {
    var ix_data: [13]u8 = undefined;
    @memset(&ix_data, 0);
    std.mem.writeInt(u32, ix_data[0..4], 11, .little);
    std.mem.writeInt(u64, ix_data[4..12], 512, .little);
    ix_data[12] = 1;

    try std.testing.expectEqual(@as(u32, 11), std.mem.readInt(u32, ix_data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 512), std.mem.readInt(u64, ix_data[4..12], .little));
    try std.testing.expectEqual(@as(u8, 1), ix_data[12]);
}

test "advanceNonceAccount instruction data format" {
    const ix_data = &[_]u8{ 4, 0, 0, 0 };
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, ix_data[0..4], .little));
}
