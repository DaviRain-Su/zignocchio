//! # Vault Program - Educational Example using Zignocchio SDK
//!
//! A minimalist lamport vault that allows users to securely store and withdraw SOL.
//! Users can deposit lamports into a PDA-based vault and withdraw them later.
//!
//! This program demonstrates:
//! - Program Derived Addresses (PDAs) for secure vault accounts
//! - Cross-Program Invocation (CPI) to System Program for transfers
//! - Single-byte discriminators for instruction routing (0 = Deposit, 1 = Withdraw)
//! - Manual account validation and security checks
//! - Signed CPI using PDAs
//!
//! ## Project Structure
//!
//! ```
//! examples/vault/
//! ├── lib.zig        # Main entrypoint with instruction routing
//! ├── deposit.zig    # Deposit instruction handler
//! └── withdraw.zig   # Withdraw instruction handler
//! ```
//!
//! ## Instructions
//!
//! ### Deposit (discriminator = 0)
//! Transfers lamports from the owner to their PDA vault.
//!
//! **Accounts:**
//! 1. Owner (signer, writable) - User depositing funds
//! 2. Vault (writable) - PDA derived from `["vault", owner_pubkey]`
//! 3. System Program - For CPI transfer
//!
//! **Instruction data:**
//! - Byte 0: Discriminator (0)
//! - Bytes 1-8: Amount (u64, little-endian)
//!
//! **Validations:**
//! - Owner must sign
//! - Vault must be owned by System Program
//! - Vault must be empty (prevents double deposits)
//! - Vault address must match expected PDA
//! - Amount must be greater than 0
//!
//! ### Withdraw (discriminator = 1)
//! Transfers all lamports from the vault back to the owner.
//!
//! **Accounts:**
//! 1. Owner (signer, writable) - User withdrawing funds
//! 2. Vault (writable) - PDA derived from `["vault", owner_pubkey]`
//! 3. System Program - For CPI transfer
//!
//! **Instruction data:**
//! - Byte 0: Discriminator (1)
//!
//! **Validations:**
//! - Owner must sign
//! - Vault must be owned by System Program
//! - Vault address must match expected PDA
//! - Vault must contain lamports
//!
//! **Note:** Uses PDA signing - the vault itself signs the transfer back to owner.
//!
//! ## Key Concepts
//!
//! ### Program Derived Addresses (PDAs)
//! ```zig
//! const seed_owner = owner.key().*;
//! const seeds = &[_][]const u8{ "vault", &seed_owner };
//! var vault_key: sdk.Pubkey = undefined;
//! var bump: u8 = undefined;
//! try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);
//! ```
//!
//! ### Cross-Program Invocation (CPI)
//! ```zig
//! const account_metas = [_]sdk.AccountMeta{
//!     .{ .pubkey = from.key(), .is_signer = true, .is_writable = true },
//!     .{ .pubkey = to.key(), .is_signer = false, .is_writable = true },
//! };
//! const instruction = sdk.Instruction{
//!     .program_id = &system_program_id,
//!     .accounts = &account_metas,
//!     .data = &transfer_ix_data,
//! };
//! try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ from, to });
//! ```
//!
//! ### Signed CPI with PDAs
//! ```zig
//! const signer_seeds = &[_][]const u8{
//!     "vault",
//!     &seed_owner,
//!     &bump_array,
//! };
//! try sdk.invokeSigned(&instruction, &[_]sdk.AccountInfo{ vault, owner }, signer_seeds);
//! ```
//!
//! ## Security Features
//! - Signer validation: Owner must sign all transactions
//! - Account ownership checks: Vault must be owned by System Program
//! - PDA verification: Vault address must match expected PDA derivation
//! - Amount validation: Prevents zero-amount transactions
//! - State validation: Prevents double deposits and empty withdrawals
//! - Atomic operations: Each instruction is self-contained
//!
//! ## sBPF Constraints
//! sBPF doesn't support aggregate returns. The SDK's `findProgramAddress` uses
//! output parameters instead of returning a struct.

const sdk = @import("sdk");
const deposit = @import("deposit.zig");
const withdraw = @import("withdraw.zig");

// NOTE: Program ID is NOT hardcoded. It's passed as a parameter to the entrypoint
// and propagated through processInstruction -> deposit/withdraw validators.
// This allows the same program binary to work with any deployed program address.

/// Program entrypoint
export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(5, processInstruction), .{input});
}

/// Process instruction - routes to appropriate handler based on discriminator
fn processInstruction(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Vault program: Starting");

    // Instruction data must have at least 1 byte (discriminator)
    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    // Read discriminator (first byte)
    const discriminator = instruction_data[0];

    // Route to appropriate instruction handler
    switch (discriminator) {
        deposit.DISCRIMINATOR => {
            sdk.logMsg("Vault: Routing to Deposit");
            // Skip discriminator byte, pass remaining data
            const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};
            return deposit.process(program_id, accounts, data);
        },
        withdraw.DISCRIMINATOR => {
            sdk.logMsg("Vault: Routing to Withdraw");
            return withdraw.process(program_id, accounts);
        },
        else => {
            sdk.logMsg("Error: Unknown instruction discriminator");
            return error.InvalidInstructionData;
        },
    }
}
