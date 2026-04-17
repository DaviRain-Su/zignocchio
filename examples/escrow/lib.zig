//! Escrow Program - Educational Example using Zignocchio SDK
//!
//! This program demonstrates:
//! - AccountSchema for typed account data
//! - Security guards (signer, pda, discriminator)
//! - System Program CPI (createAccount)
//! - Idioms (close_account)
//!
//! ## Instructions
//!
//! ### Make (discriminator = 0)
//! - Maker creates an escrow PDA and deposits lamports
//! - Instruction data: [taker_pubkey (32 bytes), amount (u64 LE)]
//!
//! ### Accept (discriminator = 1)
//! - Taker accepts the escrow and receives the lamports
//! - Escrow account is closed
//!
//! ### Refund (discriminator = 2)
//! - Maker refunds the escrow and retrieves their lamports
//! - Escrow account is closed

const sdk = @import("sdk");
const make = @import("make.zig");
const accept = @import("accept.zig");
const refund = @import("refund.zig");

/// Program entrypoint
export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(6, processInstruction), .{input});
}

/// Process instruction - routes to appropriate handler
fn processInstruction(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Escrow program: Starting");

    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    const discriminator = instruction_data[0];

    switch (discriminator) {
        make.DISCRIMINATOR => {
            sdk.logMsg("Escrow: Routing to Make");
            const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};
            return make.process(program_id, accounts, data);
        },
        accept.DISCRIMINATOR => {
            sdk.logMsg("Escrow: Routing to Accept");
            return accept.process(program_id, accounts);
        },
        refund.DISCRIMINATOR => {
            sdk.logMsg("Escrow: Routing to Refund");
            return refund.process(program_id, accounts);
        },
        else => {
            sdk.logMsg("Error: Unknown instruction discriminator");
            return error.InvalidInstructionData;
        },
    }
}
