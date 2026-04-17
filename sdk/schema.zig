//! AccountSchema comptime interface for Solana programs
//!
//! `AccountSchema(T)` provides compile-time layout verification and safe
//! deserialization for account data structs. It ensures that agent-generated
//! code cannot silently deserialize the wrong account type.

const sdk = @import("zignocchio.zig");

/// Create an AccountSchema for type `T`.
///
/// `T` must be a `packed struct` or `extern struct` with a compile-time
/// `DISCRIMINATOR` constant of type `u8`. The discriminator is used at
/// runtime to verify that the account data has the expected type.
///
/// ## Example
/// ```zig
/// const MyAccount = extern struct {
///     pub const DISCRIMINATOR: u8 = 0xAB;
///
///     discriminator: u8,
///     owner: sdk.Pubkey,
///     amount: u64,
/// };
///
/// const Schema = sdk.AccountSchema(MyAccount);
/// try Schema.validate(account);
/// var data = try Schema.from_bytes(account);
/// defer data.release();
/// data.value.amount = 42;
/// ```
pub fn AccountSchema(comptime T: type) type {
    comptime {
        const info = @typeInfo(T);
        if (info != .@"struct") {
            @compileError("AccountSchema requires a struct type, got " ++ @typeName(T));
        }
        if (info.@"struct".layout != .@"packed" and info.@"struct".layout != .@"extern") {
            @compileError("AccountSchema requires packed or extern struct layout, got " ++ @typeName(T));
        }
        if (!@hasDecl(T, "DISCRIMINATOR")) {
            @compileError("AccountSchema type must declare a `DISCRIMINATOR` constant of type u8");
        }
        if (@TypeOf(T.DISCRIMINATOR) != u8) {
            @compileError("AccountSchema `DISCRIMINATOR` must be of type u8");
        }
    }

    return struct {
        pub const LEN: usize = @sizeOf(T);
        pub const DISCRIMINATOR: u8 = T.DISCRIMINATOR;

        /// Validate that `account` has enough data and the correct discriminator.
        /// This should always be called before casting raw bytes to `T`.
        pub fn validate(account: sdk.AccountInfo) sdk.ProgramResult {
            if (account.dataLen() < LEN) {
                return error.AccountDataTooSmall;
            }
            const data = account.borrowDataUnchecked();
            if (data.len < 1 or data[0] != DISCRIMINATOR) {
                return error.InvalidAccountData;
            }
        }

        /// Deserialize account data into `*T` WITHOUT validation.
        ///
        /// **SAFETY**: Caller MUST call `validate()` first. Using this on an
        /// unvalidated account can lead to type confusion and undefined behavior.
        pub fn from_bytes_unchecked(data: []u8) *T {
            return @as(*T, @ptrCast(@alignCast(data.ptr)));
        }

        /// Safe wrapper: validate then borrow mutably.
        ///
        /// Writes the `RefMut([]u8)` result into `out_ref`. Caller must release it when done.
        /// The caller can then use `from_bytes_unchecked` on `out_ref.value`.
        pub fn from_bytes(
            account: sdk.AccountInfo,
            out_ref: *sdk.RefMut([]u8),
        ) sdk.ProgramResult {
            try validate(account);
            out_ref.* = try account.tryBorrowMutData();
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

const TestAccount = extern struct {
    pub const DISCRIMINATOR: u8 = 0xAB;

    discriminator: u8,
    owner: sdk.Pubkey,
    amount: u64,
};

const Schema = AccountSchema(TestAccount);

/// Mock layout: Account struct immediately followed by data bytes
const MockLayout = extern struct {
    account: sdk.Account,
    data: [64]u8,
};

fn makeMock(data_len: u64, data: ?[]const u8) MockLayout {
    var mock = MockLayout{
        .account = sdk.Account{
            .borrow_state = sdk.NON_DUP_MARKER,
            .is_signer = 0,
            .is_writable = 1,
            .executable = 0,
            .resize_delta = 0,
            .key = .{0} ** 32,
            .owner = .{0} ** 32,
            .lamports = 0,
            .data_len = data_len,
        },
        .data = .{0} ** 64,
    };
    if (data) |d| {
        @memcpy(mock.data[0..d.len], d);
    }
    return mock;
}

test "LEN equals struct size" {
    try std.testing.expectEqual(@sizeOf(TestAccount), Schema.LEN);
}

test "DISCRIMINATOR matches declaration" {
    try std.testing.expectEqual(0xAB, Schema.DISCRIMINATOR);
}

test "validate passes for correct data" {
    var mock = makeMock(64, &[_]u8{0xAB});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    try Schema.validate(info);
}

test "validate fails for data too small" {
    var mock = makeMock(8, &[_]u8{0xAB});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    try std.testing.expectError(error.AccountDataTooSmall, Schema.validate(info));
}

test "validate fails for empty data" {
    var mock = makeMock(0, null);
    const info = sdk.AccountInfo{ .raw = &mock.account };
    try std.testing.expectError(error.AccountDataTooSmall, Schema.validate(info));
}

test "validate fails for wrong discriminator" {
    var mock = makeMock(64, &[_]u8{0xCD});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    try std.testing.expectError(error.InvalidAccountData, Schema.validate(info));
}

test "from_bytes_unchecked returns correct pointer" {
    var mock = makeMock(64, &[_]u8{0xAB});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    // Use dataPtr to get the slice, then unchecked cast
    const data = info.borrowMutDataUnchecked();
    const ptr = Schema.from_bytes_unchecked(data);
    try std.testing.expectEqual(0xAB, ptr.discriminator);
}

test "from_bytes borrows and releases" {
    var mock = makeMock(64, &[_]u8{0xAB});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    var ref: sdk.RefMut([]u8) = undefined;
    try Schema.from_bytes(info, &ref);
    defer ref.release();
    try std.testing.expectEqual(64, ref.value.len);
}

test "from_bytes fails when data too small" {
    var mock = makeMock(8, &[_]u8{0xAB});
    const info = sdk.AccountInfo{ .raw = &mock.account };
    var ref: sdk.RefMut([]u8) = undefined;
    try std.testing.expectError(error.AccountDataTooSmall, Schema.from_bytes(info, &ref));
}

test "packed struct schema LEN" {
    const PackedAccount = packed struct {
        pub const DISCRIMINATOR: u8 = 0x12;
        flag: u1,
        value: u7,
    };
    const PackedSchema = AccountSchema(PackedAccount);
    try std.testing.expectEqual(@sizeOf(PackedAccount), PackedSchema.LEN);
}

const std = @import("std");
