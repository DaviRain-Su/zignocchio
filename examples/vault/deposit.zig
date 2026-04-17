//! Deposit Instruction
const std = @import("std");
const sdk = @import("sdk");

/// NOTE: We intentionally do NOT define SYSTEM_PROGRAM_ID as a module-level
/// constant because Zig 0.16's BPF backend places all-zero module-scope data
/// at address 0x0, which causes an access violation when we take its address.
/// Use a local `var` copy wherever the system program ID is needed.

pub const DISCRIMINATOR: u8 = 0;

pub const DepositAccounts = struct {
    owner: sdk.AccountInfo,
    vault: sdk.AccountInfo,
    system_program: sdk.AccountInfo,
};

pub const DepositData = struct {
    amount: u64,
};

pub fn getSystemProgramId() sdk.Pubkey {
    return .{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
}

pub fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!DepositAccounts {
    sdk.logMsg("Deposit validate: checking account count");
    if (accounts.len < 3) {
        sdk.logMsg("Error: Not enough accounts for deposit");
        return error.NotEnoughAccountKeys;
    }

    sdk.logMsg("Deposit validate: getting accounts");
    const owner = accounts[0];
    const vault = accounts[1];
    const system_program = accounts[2];

    sdk.logMsg("Deposit validate: checking owner signer");
    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    sdk.logMsg("Deposit validate: checking vault owner");
    var system_program_id = getSystemProgramId();
    if (!sdk.pubkeyEq(vault.owner(), &system_program_id)) {
        sdk.logMsg("Error: Vault must be owned by System Program");
        return error.IncorrectProgramId;
    }

    sdk.logMsg("Deposit validate: checking vault lamports");
    if (vault.lamports() != 0) {
        sdk.logMsg("Error: Vault must be empty");
        return error.InvalidAccountData;
    }

    sdk.logMsg("Deposit validate: deriving PDA");
    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);

    sdk.logMsg("Deposit validate: checking vault PDA");
    if (!sdk.pubkeyEq(vault.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault PDA");
        return error.IncorrectProgramId;
    }

    sdk.logMsg("Deposit validate: checking system program");
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    sdk.logMsg("Deposit validate: done");
    return DepositAccounts{
        .owner = owner,
        .vault = vault,
        .system_program = system_program,
    };
}

pub fn parseData(data: []const u8) sdk.ProgramError!DepositData {
    if (data.len != 8) {
        sdk.logMsg("Error: Invalid deposit data length");
        return error.InvalidInstructionData;
    }
    const amount = std.mem.readInt(u64, data[0..8], .little);
    if (amount == 0) {
        sdk.logMsg("Error: Deposit amount must be greater than 0");
        return error.InvalidInstructionData;
    }
    return DepositData{ .amount = amount };
}

pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Deposit: Starting");
    const validated = try validateAccounts(accounts, program_id);
    const data = try parseData(instruction_data);
    sdk.logMsg("Deposit: Validated accounts and data");
    sdk.logMsg("Deposit amount:");
    sdk.logU64(data.amount);

    const transfer_ix_data = createTransferInstruction(data.amount);
    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = validated.owner.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = validated.vault.key(), .is_signer = false, .is_writable = true },
    };

    var system_program_id = getSystemProgramId();
    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &transfer_ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ validated.owner, validated.vault });
    sdk.logMsg("Deposit: Transfer completed successfully");
}

fn createTransferInstruction(amount: u64) [12]u8 {
    var data: [12]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], 2, .little);
    std.mem.writeInt(u64, data[4..12], amount, .little);
    return data;
}
