//! Security guard helpers for Solana programs
//!
//! These functions perform common security checks that every Solana instruction
//! handler should execute before processing state mutations.

const sdk = @import("zignocchio.zig");

/// Assert that the account is a signer.
/// This prevents unauthorized accounts from executing privileged instructions.
/// Fails with `MissingRequiredSignature` if the account did not sign the transaction.
pub fn assert_signer(account: sdk.AccountInfo) sdk.ProgramResult {
    if (!account.isSigner()) {
        return error.MissingRequiredSignature;
    }
}

/// Assert that the account is writable.
/// This prevents immutable accounts from being mutated.
/// Fails with `ImmutableAccount` if the account is not marked writable.
pub fn assert_writable(account: sdk.AccountInfo) sdk.ProgramResult {
    if (!account.isWritable()) {
        return error.ImmutableAccount;
    }
}

/// Assert that the account is owned by the expected program.
/// This prevents attackers from passing forged accounts that mimic the shape
/// of your program's accounts but are controlled by a different program.
/// Fails with `IncorrectProgramId` if ownership does not match.
pub fn assert_owner(account: sdk.AccountInfo, expected: *const sdk.Pubkey) sdk.ProgramResult {
    if (!sdk.pubkeyEq(account.owner(), expected)) {
        return error.IncorrectProgramId;
    }
}

/// Assert that the account's key matches the PDA derived from seeds + program_id + bump.
/// This ensures the provided account address was legitimately derived and not spoofed.
/// Fails with `IncorrectProgramId` if the derivation does not match.
pub fn assert_pda(
    account: sdk.AccountInfo,
    seeds: []const []const u8,
    program_id: *const sdk.Pubkey,
    bump: u8,
) sdk.ProgramResult {
    if (seeds.len > sdk.MAX_SEEDS) {
        return error.IncorrectProgramId;
    }

    var all_seeds: [sdk.MAX_SEEDS + 1][]const u8 = undefined;
    for (seeds, 0..) |seed, i| {
        all_seeds[i] = seed;
    }
    const bump_seed = &[_]u8{bump};
    all_seeds[seeds.len] = bump_seed;

    var expected: sdk.Pubkey = undefined;
    sdk.createProgramAddress(all_seeds[0 .. seeds.len + 1], program_id, &expected) catch {
        return error.IncorrectProgramId;
    };

    if (!sdk.pubkeyEq(account.key(), &expected)) {
        return error.IncorrectProgramId;
    }
}

/// Assert that the account data starts with the expected discriminator byte.
/// Discriminators prevent type confusion when multiple account types share
/// the same owner program. Always check the discriminator before casting
/// raw bytes to a structured account type.
/// Fails with `InvalidAccountData` if data is too short or the first byte mismatches.
pub fn assert_discriminator(data: []const u8, expected: u8) sdk.ProgramResult {
    if (data.len < 1 or data[0] != expected) {
        return error.InvalidAccountData;
    }
}

/// Assert that an account has enough lamports to be rent exempt for the given data size.
/// On Solana, all new accounts must be rent exempt. This check prevents
/// account creation transactions from silently creating rent-paying accounts
/// that could be drained by the rent collector.
///
/// Uses a conservative approximation: `required = ((data_len / 256) + 1) * 6960`.
/// This may slightly overestimate for small accounts, ensuring safety.
/// Fails with `AccountNotRentExempt` if lamports are insufficient.
pub fn assert_rent_exempt(lamports: u64, data_len: usize) sdk.ProgramResult {
    const required = ((data_len / 256) + 1) * 6960;
    if (lamports < required) {
        return error.AccountNotRentExempt;
    }
}

/// Assert that the account data is not all zeros.
/// This is useful for ensuring that an account has already been initialized
/// and contains meaningful state rather than empty memory.
/// Fails with `UninitializedAccount` if every byte is zero.
pub fn assert_initialized(data: []const u8) sdk.ProgramResult {
    for (data) |byte| {
        if (byte != 0) return;
    }
    return error.UninitializedAccount;
}

/// Assert that the account data is all zeros.
/// This is useful for ensuring that an account has not yet been initialized,
/// preventing accidental overwrite of existing state.
/// Fails with `AccountAlreadyInitialized` if any byte is non-zero.
pub fn assert_uninitialized(data: []const u8) sdk.ProgramResult {
    for (data) |byte| {
        if (byte != 0) {
            return error.AccountAlreadyInitialized;
        }
    }
}

/// Assert that the account data length is at least the expected minimum.
/// This prevents deserialization errors when an account with insufficient data
/// is passed to an instruction that expects a larger struct.
/// Fails with `AccountDataTooSmall` if the length is insufficient.
pub fn assert_min_data_len(account: sdk.AccountInfo, min_len: usize) sdk.ProgramResult {
    if (account.dataLen() < min_len) {
        return error.AccountDataTooSmall;
    }
}

/// Assert that two account keys are not the same.
/// This prevents passing the same account twice for operations that require
/// distinct accounts (e.g., swap, transfer from A to B).
/// Fails with `InvalidArgument` if the keys are equal.
pub fn assert_keys_not_equal(a: sdk.AccountInfo, b: sdk.AccountInfo) sdk.ProgramResult {
    if (sdk.pubkeyEq(a.key(), b.key())) {
        return error.InvalidArgument;
    }
}

/// Assert that a program ID matches the expected value.
/// Use this to verify that the instruction is being executed by the correct
/// program, or that a passed-in program account is the one you expect.
/// Fails with `IncorrectProgramId` if the keys do not match.
pub fn assert_program_id(actual: *const sdk.Pubkey, expected: *const sdk.Pubkey) sdk.ProgramResult {
    if (!sdk.pubkeyEq(actual, expected)) {
        return error.IncorrectProgramId;
    }
}

/// Assert that the account is marked executable.
/// Use this when an instruction requires a program account (e.g. for CPI).
/// Fails with `InvalidArgument` if the account is not executable.
pub fn assert_executable(account: sdk.AccountInfo) sdk.ProgramResult {
    if (!account.executable()) {
        return error.InvalidArgument;
    }
}

/// Assert that the account is NOT writable (immutable).
/// This is the inverse of `assert_writable` and is useful when an account
/// must remain unchanged for the duration of the instruction.
/// Fails with `ImmutableAccount` if the account is writable.
pub fn assert_immutable(account: sdk.AccountInfo) sdk.ProgramResult {
    if (account.isWritable()) {
        return error.ImmutableAccount;
    }
}

// =============================================================================
// Tests
// =============================================================================

test "assert_signer passes for signer" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 1, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_signer(info);
}

test "assert_signer fails for non-signer" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.MissingRequiredSignature, assert_signer(info));
}

test "assert_writable passes for writable" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_writable(info);
}

test "assert_writable fails for immutable" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.ImmutableAccount, assert_writable(info));
}

test "assert_owner passes for matching owner" {
    const owner: sdk.Pubkey align(8) = .{1} ** 32;
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = owner, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_owner(info, &owner);
}

test "assert_owner fails for mismatching owner" {
    const owner: sdk.Pubkey align(8) = .{1} ** 32;
    const wrong: sdk.Pubkey align(8) = .{2} ** 32;
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = wrong, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.IncorrectProgramId, assert_owner(info, &owner));
}

// NOTE: assert_pda tests that call createProgramAddress cannot run on the host
// because they depend on Solana syscalls. The happy path and bump-mismatch
// tests are covered in surfpool integration tests.

test "assert_pda fails for too many seeds" {
    const program_id: sdk.Pubkey align(8) = .{0} ** 32;
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    const seeds = &[_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17" };
    try std.testing.expectError(error.IncorrectProgramId, assert_pda(info, seeds, &program_id, 255));
}

test "assert_discriminator passes for matching byte" {
    const data = &[_]u8{0xAB, 0x00, 0x00};
    try assert_discriminator(data, 0xAB);
}

test "assert_discriminator fails for mismatch" {
    const data = &[_]u8{0xAB, 0x00, 0x00};
    try std.testing.expectError(error.InvalidAccountData, assert_discriminator(data, 0xCD));
}

test "assert_discriminator fails for empty data" {
    const data = &[_]u8{};
    try std.testing.expectError(error.InvalidAccountData, assert_discriminator(data, 0xAB));
}

test "assert_rent_exempt passes for sufficient lamports" {
    // data_len = 0 => required = 6960
    try assert_rent_exempt(6960, 0);
    try assert_rent_exempt(10000, 0);
}

test "assert_rent_exempt fails for insufficient lamports" {
    try std.testing.expectError(error.AccountNotRentExempt, assert_rent_exempt(6959, 0));
}

test "assert_rent_exempt boundary at 256 bytes" {
    // data_len = 256 => required = ((256/256)+1)*6960 = 13920
    try assert_rent_exempt(13920, 256);
    try std.testing.expectError(error.AccountNotRentExempt, assert_rent_exempt(13919, 256));
}

// --- assert_initialized / assert_uninitialized ---

test "assert_initialized passes for non-zero data" {
    const data = &[_]u8{0, 0, 1, 0};
    try assert_initialized(data);
}

test "assert_initialized fails for all-zero data" {
    const data = &[_]u8{0, 0, 0, 0};
    try std.testing.expectError(error.UninitializedAccount, assert_initialized(data));
}

test "assert_initialized fails for empty data" {
    const data = &[_]u8{};
    try std.testing.expectError(error.UninitializedAccount, assert_initialized(data));
}

test "assert_uninitialized passes for all-zero data" {
    const data = &[_]u8{0, 0, 0, 0};
    try assert_uninitialized(data);
}

test "assert_uninitialized passes for empty data" {
    const data = &[_]u8{};
    try assert_uninitialized(data);
}

test "assert_uninitialized fails for non-zero data" {
    const data = &[_]u8{0, 0, 1, 0};
    try std.testing.expectError(error.AccountAlreadyInitialized, assert_uninitialized(data));
}

// --- assert_min_data_len ---

test "assert_min_data_len passes for sufficient length" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 64 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_min_data_len(info, 64);
    try assert_min_data_len(info, 32);
}

test "assert_min_data_len fails for insufficient length" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 10 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.AccountDataTooSmall, assert_min_data_len(info, 11));
}

// --- assert_keys_not_equal ---

test "assert_keys_not_equal passes for different keys" {
    var a = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{1} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    var b = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{2} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    try assert_keys_not_equal(sdk.AccountInfo{ .raw = &a }, sdk.AccountInfo{ .raw = &b });
}

test "assert_keys_not_equal fails for same key" {
    var a = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{1} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    var b = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{1} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    try std.testing.expectError(error.InvalidArgument, assert_keys_not_equal(sdk.AccountInfo{ .raw = &a }, sdk.AccountInfo{ .raw = &b }));
}

// --- assert_program_id ---

test "assert_program_id passes for matching id" {
    const id: sdk.Pubkey align(8) = .{3} ** 32;
    try assert_program_id(&id, &id);
}

test "assert_program_id fails for mismatching id" {
    const a: sdk.Pubkey align(8) = .{3} ** 32;
    const b: sdk.Pubkey align(8) = .{4} ** 32;
    try std.testing.expectError(error.IncorrectProgramId, assert_program_id(&a, &b));
}

// --- assert_executable ---

test "assert_executable passes for executable account" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 1, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_executable(info);
}

test "assert_executable fails for non-executable account" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.InvalidArgument, assert_executable(info));
}

// --- assert_immutable ---

test "assert_immutable passes for immutable account" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 0, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try assert_immutable(info);
}

test "assert_immutable fails for writable account" {
    var account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    const info = sdk.AccountInfo{ .raw = &account };
    try std.testing.expectError(error.ImmutableAccount, assert_immutable(info));
}

const std = @import("std");
