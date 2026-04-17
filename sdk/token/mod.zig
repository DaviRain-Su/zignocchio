//! SPL Token Program support
//!
//! This module provides constants and types for interacting with the SPL Token program.

const std = @import("std");
const types = @import("../types.zig");

// Re-export token state modules
pub const mint = @import("mint.zig");
pub const account = @import("account.zig");
pub const instructions = @import("instructions/mod.zig");

// Re-export CPI wrappers
pub const ata = @import("ata.zig");
pub const transfer = @import("transfer.zig");
pub const close_account = @import("close_account.zig");

// Re-export commonly used types
pub const Mint = mint.Mint;
pub const TokenAccount = account.TokenAccount;

/// SPL Token Program ID: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
///
/// ⚠️ WARNING (Zig 0.16 BPF): Do NOT take the address of this constant
/// (`&TOKEN_PROGRAM_ID`) directly. Due to a backend quirk, module-scope const
/// arrays may be placed at invalid low addresses (e.g. `0x0`) in the final ELF.
/// Always use `getTokenProgramId(&local_var)` to obtain a valid stack copy.
pub const TOKEN_PROGRAM_ID: types.Pubkey = .{
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93,
    0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91,
    0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9,
};

/// Writes the SPL Token Program ID into `out` byte-by-byte.
/// This avoids loading from the module-scope `TOKEN_PROGRAM_ID`, which the
/// Zig 0.16 BPF backend places at an invalid low address.
pub fn getTokenProgramId(out: *types.Pubkey) void {
    out[0] = 0x06;
    out[1] = 0xdd;
    out[2] = 0xf6;
    out[3] = 0xe1;
    out[4] = 0xd7;
    out[5] = 0x65;
    out[6] = 0xa1;
    out[7] = 0x93;
    out[8] = 0xd9;
    out[9] = 0xcb;
    out[10] = 0xe1;
    out[11] = 0x46;
    out[12] = 0xce;
    out[13] = 0xeb;
    out[14] = 0x79;
    out[15] = 0xac;
    out[16] = 0x1c;
    out[17] = 0xb4;
    out[18] = 0x85;
    out[19] = 0xed;
    out[20] = 0x5f;
    out[21] = 0x5b;
    out[22] = 0x37;
    out[23] = 0x91;
    out[24] = 0x3a;
    out[25] = 0x8c;
    out[26] = 0xf5;
    out[27] = 0x85;
    out[28] = 0x7e;
    out[29] = 0xff;
    out[30] = 0x00;
    out[31] = 0xa9;
}

/// Account state as stored by the SPL Token program
pub const AccountState = enum(u8) {
    /// Account is not yet initialized
    Uninitialized = 0,
    /// Account is initialized; the account owner and/or delegate may perform permitted operations
    Initialized = 1,
    /// Account has been frozen by the mint freeze authority. Neither the account owner nor
    /// the delegate are able to perform operations on this account.
    Frozen = 2,
};
