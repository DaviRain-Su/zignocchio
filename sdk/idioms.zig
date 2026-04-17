//! Common idioms and utility helpers for Solana programs
//!
//! These functions encapsulate high-frequency operations to reduce boilerplate
//! and help agents produce correct, idiomatic Zig code.

const sdk = @import("zignocchio.zig");
const std = @import("std");

/// Close an account by transferring all lamports to the destination
/// and zeroing out the account data (first byte set to 0).
///
/// **IMPORTANT**: This directly modifies lamports without invoking the
/// System Program. This is the standard Pinocchio idiom *within a single
/// transaction*. For transferring lamports across transactions, always use
/// `system.transfer`.
///
/// The account is not reallocated; it is drained and its discriminator
/// is cleared so that subsequent `assert_discriminator` calls will fail.
pub fn close_account(account: sdk.AccountInfo, destination: sdk.AccountInfo) sdk.ProgramResult {
    var dest_lamports = try destination.tryBorrowMutLamports();
    defer dest_lamports.release();

    var src_lamports = try account.tryBorrowMutLamports();
    defer src_lamports.release();

    const amount = src_lamports.value.*;
    src_lamports.value.* = 0;
    dest_lamports.value.* += amount;

    // Zero out first byte as discriminator clear
    var data = account.borrowMutDataUnchecked();
    if (data.len > 0) {
        data[0] = 0;
    }
}

/// Read a little-endian u64 from account data at the given offset.
/// Fails with `InvalidAccountData` if `offset + 8 > data.len`.
pub fn read_u64_le(data: []const u8, offset: usize) sdk.ProgramError!u64 {
    if (offset + 8 > data.len) {
        return error.InvalidAccountData;
    }
    return std.mem.readInt(u64, data[offset..][0..8], .little);
}

/// Write a little-endian u64 to account data at the given offset.
/// Fails with `InvalidAccountData` if `offset + 8 > data.len`.
pub fn write_u64_le(data: []u8, offset: usize, value: u64) sdk.ProgramResult {
    if (offset + 8 > data.len) {
        return error.InvalidAccountData;
    }
    std.mem.writeInt(u64, data[offset..][0..8], value, .little);
}

/// Read a Pubkey (32 bytes) from account data at the given offset.
/// Fails with `InvalidAccountData` if `offset + 32 > data.len`.
pub fn read_pubkey(data: []const u8, offset: usize) sdk.ProgramError!sdk.Pubkey {
    if (offset + 32 > data.len) {
        return error.InvalidAccountData;
    }
    var pk: sdk.Pubkey = undefined;
    @memcpy(&pk, data[offset .. offset + 32]);
    return pk;
}

// =============================================================================
// Tests
// =============================================================================

test "close_account drains lamports and clears discriminator" {
    var dest_account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 100, .data_len = 0 };
    var src_account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{1} ** 32, .owner = .{0} ** 32, .lamports = 500, .data_len = 0 };

    const dest = sdk.AccountInfo{ .raw = &dest_account };
    const src = sdk.AccountInfo{ .raw = &src_account };

    try close_account(src, dest);

    try std.testing.expectEqual(600, dest_account.lamports);
    try std.testing.expectEqual(0, src_account.lamports);
}

test "close_account with zero data len does not crash" {
    var dest_account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };
    var src_account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{1} ** 32, .owner = .{0} ** 32, .lamports = 0, .data_len = 0 };

    const dest = sdk.AccountInfo{ .raw = &dest_account };
    const src = sdk.AccountInfo{ .raw = &src_account };
    try close_account(src, dest);
}

const MockLayout = extern struct {
    account: sdk.Account,
    data: [64]u8,
};

test "close_account clears discriminator via mock layout" {
    var mock = MockLayout{
        .account = sdk.Account{
            .borrow_state = sdk.NON_DUP_MARKER,
            .is_signer = 0,
            .is_writable = 1,
            .executable = 0,
            .resize_delta = 0,
            .key = .{1} ** 32,
            .owner = .{0} ** 32,
            .lamports = 100,
            .data_len = 64,
        },
        .data = .{0xAB} ** 64,
    };
    var dest_account = sdk.Account{ .borrow_state = sdk.NON_DUP_MARKER, .is_signer = 0, .is_writable = 1, .executable = 0, .resize_delta = 0, .key = .{0} ** 32, .owner = .{0} ** 32, .lamports = 50, .data_len = 0 };

    const src = sdk.AccountInfo{ .raw = &mock.account };
    const dest = sdk.AccountInfo{ .raw = &dest_account };
    try close_account(src, dest);

    try std.testing.expectEqual(0, mock.data[0]);
    try std.testing.expectEqual(150, dest_account.lamports);
    try std.testing.expectEqual(0, mock.account.lamports);
}

test "read_u64_le happy path" {
    var data = [_]u8{0} ** 16;
    const value: u64 = 0x0102030405060708;
    std.mem.writeInt(u64, data[0..8], value, .little);
    const result = try read_u64_le(&data, 0);
    try std.testing.expectEqual(value, result);
}

test "read_u64_le at boundary" {
    var data = [_]u8{0} ** 16;
    const value: u64 = 0xDEADBEEFCAFEBABE;
    std.mem.writeInt(u64, data[8..16], value, .little);
    const result = try read_u64_le(&data, 8);
    try std.testing.expectEqual(value, result);
}

test "read_u64_le fails when offset too large" {
    var data = [_]u8{0} ** 15;
    try std.testing.expectError(error.InvalidAccountData, read_u64_le(&data, 8));
}

test "write_u64_le happy path" {
    var data = [_]u8{0} ** 16;
    const value: u64 = 0x0102030405060708;
    try write_u64_le(&data, 0, value);
    const result = std.mem.readInt(u64, data[0..8], .little);
    try std.testing.expectEqual(value, result);
}

test "write_u64_le at boundary" {
    var data = [_]u8{0} ** 16;
    const value: u64 = 0xDEADBEEFCAFEBABE;
    try write_u64_le(&data, 8, value);
    const result = std.mem.readInt(u64, data[8..16], .little);
    try std.testing.expectEqual(value, result);
}

test "write_u64_le fails when offset too large" {
    var data = [_]u8{0} ** 15;
    try std.testing.expectError(error.InvalidAccountData, write_u64_le(&data, 8, 1));
}

test "read_pubkey happy path" {
    const expected: sdk.Pubkey = .{0xAB} ** 32;
    var data = [_]u8{0} ** 64;
    @memcpy(data[0..32], &expected);
    const result = try read_pubkey(&data, 0);
    try std.testing.expectEqual(expected, result);
}

test "read_pubkey at boundary" {
    const expected: sdk.Pubkey = .{0xCD} ** 32;
    var data = [_]u8{0} ** 64;
    @memcpy(data[32..64], &expected);
    const result = try read_pubkey(&data, 32);
    try std.testing.expectEqual(expected, result);
}

test "read_pubkey fails when offset too large" {
    var data = [_]u8{0} ** 63;
    try std.testing.expectError(error.InvalidAccountData, read_pubkey(&data, 32));
}
