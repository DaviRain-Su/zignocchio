//! PDA Storage - Simple PDA read/write example
//!
//! This program demonstrates:
//! - PDA derivation and validation
//! - Creating a PDA via System Program CPI
//! - Reading and writing u64 data to a PDA
//! - Discriminator-based instruction routing

const sdk = @import("sdk");
const std = @import("std");

const DISCRIMINATOR_INIT = 0;
const DISCRIMINATOR_UPDATE = 1;
const STORAGE_SEED = "storage";

/// Program entrypoint
export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(4, processInstruction), .{input});
}

/// Process instruction
///
/// Accounts for Init (discriminator = 0):
/// - 0: payer (signer, writable)
/// - 1: storage_pda (writable) — derived from ["storage", user_pubkey]
/// - 2: user (signer) — the owner of this storage
/// - 3: system_program
///
/// Instruction data for Init: [discriminator: u8, initial_value: u64 LE]
///
/// Accounts for Update (discriminator = 1):
/// - 0: storage_pda (writable)
/// - 1: user (signer) — must match the owner stored in PDA
///
/// Instruction data for Update: [discriminator: u8, new_value: u64 LE]
fn processInstruction(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("PDA Storage: starting");

    if (instruction_data.len < 1) {
        sdk.logMsg("Error: Missing discriminator");
        return error.InvalidInstructionData;
    }

    const discriminator = instruction_data[0];

    switch (discriminator) {
        DISCRIMINATOR_INIT => return try initStorage(program_id, accounts, instruction_data),
        DISCRIMINATOR_UPDATE => return try updateStorage(program_id, accounts, instruction_data),
        else => {
            sdk.logMsg("Error: Unknown discriminator");
            return error.InvalidInstructionData;
        },
    }
}

fn initStorage(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    if (accounts.len < 4) {
        sdk.logMsg("Error: Not enough accounts for init");
        return error.NotEnoughAccountKeys;
    }

    const payer = accounts[0];
    const storage_pda = accounts[1];
    const user = accounts[2];

    // Validate payer and user are signers
    if (!payer.isSigner()) return error.MissingRequiredSignature;
    if (!user.isSigner()) return error.MissingRequiredSignature;

    // Validate writable
    if (!payer.isWritable()) return error.ImmutableAccount;
    if (!storage_pda.isWritable()) return error.ImmutableAccount;

    // Parse initial value
    if (instruction_data.len < 9) {
        sdk.logMsg("Error: Instruction data too short for init");
        return error.InvalidInstructionData;
    }
    const initial_value = std.mem.readInt(u64, instruction_data[1..9], .little);

    // Derive expected PDA
    const seeds = &[_][]const u8{
        STORAGE_SEED,
        user.key()[0..32],
    };
    var expected_pda: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_pda, &bump);

    // Validate passed PDA matches derived address
    if (!sdk.pubkeyEq(storage_pda.key(), &expected_pda)) {
        sdk.logMsg("Error: Invalid PDA");
        return error.InvalidArgument;
    }

    // Create account via System Program CPI
    const space: u64 = 40; // 32 bytes owner pubkey + 8 bytes value
    // Rent-exempt minimum for ~40 bytes on Solana test validators is ~1,169,280 lamports.
    // Using a conservative fixed value to keep the example self-contained.
    const rent_exempt: u64 = 1_200_000;

    const signer_seeds = &[_][]const u8{
        STORAGE_SEED,
        user.key()[0..32],
        &[_]u8{bump},
    };

    try sdk.system.createAccountSigned(
        payer,
        storage_pda,
        program_id,
        space,
        rent_exempt,
        signer_seeds,
    );

    // Write initial data
    var data = try storage_pda.tryBorrowMutData();
    defer data.release();

    if (data.value.len < 40) {
        sdk.logMsg("Error: Account data too small");
        return error.AccountDataTooSmall;
    }

    @memcpy(data.value[0..32], user.key()[0..32]);
    std.mem.writeInt(u64, data.value[32..40], initial_value, .little);

    sdk.logMsg("PDA Storage: initialized with value");
    sdk.logU64(initial_value);

    return {};
}

fn updateStorage(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    if (accounts.len < 2) {
        sdk.logMsg("Error: Not enough accounts for update");
        return error.NotEnoughAccountKeys;
    }

    const storage_pda = accounts[0];
    const user = accounts[1];

    // Validate user is signer
    if (!user.isSigner()) return error.MissingRequiredSignature;
    if (!storage_pda.isWritable()) return error.ImmutableAccount;

    // Parse new value
    if (instruction_data.len < 9) {
        sdk.logMsg("Error: Instruction data too short for update");
        return error.InvalidInstructionData;
    }
    const new_value = std.mem.readInt(u64, instruction_data[1..9], .little);

    // Validate PDA
    const seeds = &[_][]const u8{
        STORAGE_SEED,
        user.key()[0..32],
    };
    var expected_pda: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_pda, &bump);

    if (!sdk.pubkeyEq(storage_pda.key(), &expected_pda)) {
        sdk.logMsg("Error: Invalid PDA");
        return error.InvalidArgument;
    }

    // Validate ownership stored in account data
    var data = try storage_pda.tryBorrowMutData();
    defer data.release();

    if (data.value.len < 40) {
        sdk.logMsg("Error: Account data too small");
        return error.AccountDataTooSmall;
    }

    if (!sdk.pubkeyEq(data.value[0..32], user.key())) {
        sdk.logMsg("Error: User does not own this storage");
        return error.IllegalOwner;
    }

    // Update value
    std.mem.writeInt(u64, data.value[32..40], new_value, .little);

    sdk.logMsg("PDA Storage: updated to value");
    sdk.logU64(new_value);

    return {};
}
