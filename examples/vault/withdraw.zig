//! Withdraw Instruction
const std = @import("std");
const sdk = @import("sdk");
const deposit = @import("deposit.zig");

pub const DISCRIMINATOR: u8 = 1;

pub const WithdrawAccounts = struct {
    owner: sdk.AccountInfo,
    vault: sdk.AccountInfo,
    system_program: sdk.AccountInfo,
    bump: u8,
};

pub fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!WithdrawAccounts {
    if (accounts.len < 3) {
        sdk.logMsg("Error: Not enough accounts for withdraw");
        return error.NotEnoughAccountKeys;
    }

    const owner = accounts[0];
    const vault = accounts[1];
    const system_program = accounts[2];

    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    var system_program_id = deposit.getSystemProgramId();
    if (!sdk.pubkeyEq(vault.owner(), &system_program_id)) {
        sdk.logMsg("Error: Vault must be owned by System Program");
        return error.IncorrectProgramId;
    }

    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);

    if (!sdk.pubkeyEq(vault.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault PDA");
        return error.IncorrectProgramId;
    }

    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    return WithdrawAccounts{
        .owner = owner,
        .vault = vault,
        .system_program = system_program,
        .bump = bump,
    };
}

pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
) sdk.ProgramResult {
    sdk.logMsg("Withdraw: Starting");

    const validated = try validateAccounts(accounts, program_id);

    const amount = validated.vault.lamports();

    sdk.logMsg("Withdraw: Validated accounts");
    sdk.logMsg("Withdraw amount:");
    sdk.logU64(amount);

    if (amount == 0) {
        sdk.logMsg("Error: Vault is empty");
        return error.InsufficientFunds;
    }

    const transfer_ix_data = createTransferInstruction(amount);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = validated.vault.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = validated.owner.key(), .is_signer = false, .is_writable = true },
    };

    var system_program_id = deposit.getSystemProgramId();
    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &transfer_ix_data,
    };

    const seed_owner = validated.owner.key().*;
    const bump_array = [_]u8{validated.bump};
    const signer_seeds = &[_][]const u8{
        "vault",
        seed_owner[0..],
        bump_array[0..],
    };

    try sdk.invokeSigned(&instruction, &[_]sdk.AccountInfo{ validated.vault, validated.owner }, signer_seeds);

    sdk.logMsg("Withdraw: Transfer completed successfully");
}

fn createTransferInstruction(amount: u64) [12]u8 {
    var data: [12]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], 2, .little);
    std.mem.writeInt(u64, data[4..12], amount, .little);
    return data;
}
