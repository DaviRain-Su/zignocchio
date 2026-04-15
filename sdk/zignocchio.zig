//! # Zignocchio
//!
//! A zero-dependency Zig SDK for building Solana programs.
//!
//! ## Features
//! - Zero dependencies
//! - Zero-copy input deserialization
//! - Efficient borrow tracking
//! - Type-safe API
//! - Minimal compute unit consumption
//!
//! ## Important: Zig 0.16 BPF Pitfalls
//!
//! Zig 0.16's BPF backend has a known quirk where **module-scope `const` arrays
//! (especially all-zero arrays) can be placed at invalid low addresses** such as
//! `0x0` or `0x20` in the generated ELF. Taking the address of such constants
//! (`&MY_CONSTANT`) and passing it to syscalls or CPI will result in an
//! `Access violation in unknown section` at runtime.
//!
//! ### Rule of thumb
//! Whenever you need a fixed Program ID or other module-level constant and must
//! pass a pointer to it, **copy the value to a local variable first**:
//!
//! ```zig
//! // BAD - may crash at runtime on Zig 0.16
//! // if (!sdk.pubkeyEq(account.owner(), &SYSTEM_PROGRAM_ID)) { ... }
//!
//! // GOOD - stack copy guarantees a valid address
//! var system_program_id: sdk.Pubkey = .{
//!     0, 0, 0, 0, 0, 0, 0, 0,
//!     0, 0, 0, 0, 0, 0, 0, 0,
//!     0, 0, 0, 0, 0, 0, 0, 0,
//!     0, 0, 0, 0, 0, 0, 0, 0,
//! };
//! if (!sdk.pubkeyEq(account.owner(), &system_program_id)) { ... }
//! ```
//!
//! The SDK's built-in helpers (e.g. `sdk.token.getTokenProgramId(&out)`) already
//! follow this pattern. If you add new module-level constants, make sure to do
//! the same.
//!
//! ## Example
//! ```zig
//! const sdk = @import("sdk/zignocchio.zig");
//!
//! export fn entrypoint(input: [*]u8) u64 {
//!     return @call(.always_inline, sdk.entrypoint(10, processInstruction), .{input});
//! }
//!
//! fn processInstruction(
//!     program_id: *const sdk.Pubkey,
//!     accounts: []sdk.AccountInfo,
//!     instruction_data: []const u8,
//! ) sdk.ProgramResult {
//!     sdk.log("Hello from Zignocchio!");
//!     return .{};
//! }
//! ```

// Re-export all modules
pub const errors = @import("errors.zig");
pub const types = @import("types.zig");
pub const syscalls = @import("syscalls.zig");
pub const log = @import("log.zig");
pub const entrypoint = @import("entrypoint.zig");
pub const allocator = @import("allocator.zig");
pub const pda = @import("pda.zig");
pub const cpi = @import("cpi.zig");
pub const token = @import("token/mod.zig");
pub const guard = @import("guard.zig");
pub const schema = @import("schema.zig");
pub const system = @import("system.zig");
pub const idioms = @import("idioms.zig");
pub const anti_patterns = @import("anti_patterns.zig");
pub const memo = @import("memo.zig");
pub const token_2022 = @import("token_2022.zig");

// Re-export commonly used types
pub const ProgramError = errors.ProgramError;
pub const ProgramResult = errors.ProgramResult;
pub const SUCCESS = errors.SUCCESS;

pub const Pubkey = types.Pubkey;
pub const Account = types.Account;
pub const AccountInfo = types.AccountInfo;
pub const BorrowState = types.BorrowState;
pub const Ref = types.Ref;
pub const RefMut = types.RefMut;

pub const PUBKEY_BYTES = types.PUBKEY_BYTES;
pub const MAX_TX_ACCOUNTS = types.MAX_TX_ACCOUNTS;
pub const NON_DUP_MARKER = types.NON_DUP_MARKER;
pub const MAX_PERMITTED_DATA_INCREASE = types.MAX_PERMITTED_DATA_INCREASE;

// Re-export utility functions
pub const pubkeyEq = types.pubkeyEq;
pub const deserialize = entrypoint.deserialize;

// Re-export logging
pub const logMsg = log.log;
pub const logU64 = log.logU64;
pub const log64 = log.log64;
pub const logPubkey = log.logPubkey;
pub const logComputeUnits = log.logComputeUnits;
pub const getRemainingComputeUnits = log.getRemainingComputeUnits;

// Re-export allocator
pub const BumpAllocator = allocator.BumpAllocator;

// Re-export PDA functions
pub const findProgramAddress = pda.findProgramAddress;
pub const createProgramAddress = pda.createProgramAddress;
pub const createWithSeed = pda.createWithSeed;
pub const MAX_SEEDS = pda.MAX_SEEDS;
pub const MAX_SEED_LEN = pda.MAX_SEED_LEN;

// Re-export CPI
pub const AccountMeta = cpi.AccountMeta;
pub const Instruction = cpi.Instruction;
pub const invoke = cpi.invoke;
pub const invokeSigned = cpi.invokeSigned;
pub const setReturnData = cpi.setReturnData;
pub const getReturnData = cpi.getReturnData;

/// Create a program entrypoint with default max accounts (254)
pub fn createEntrypoint(
    comptime process_instruction: entrypoint.EntrypointFn,
) fn ([*]u8) callconv(.c) u64 {
    return entrypoint.entrypoint(MAX_TX_ACCOUNTS, process_instruction);
}

/// Create a program entrypoint with custom max accounts
pub fn createEntrypointWithMaxAccounts(
    comptime max_accounts: usize,
    comptime process_instruction: entrypoint.EntrypointFn,
) fn ([*]u8) callconv(.c) u64 {
    return entrypoint.entrypoint(max_accounts, process_instruction);
}
