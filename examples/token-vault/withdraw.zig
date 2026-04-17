//! Withdraw Instruction
//!
//! Handles token withdrawals from the vault.
//! Uses PDA signing to transfer tokens from vault back to user.

const std = @import("std");
const sdk = @import("sdk");

/// Discriminator for withdraw instruction
pub const DISCRIMINATOR: u8 = 1;

/// Validated accounts for withdraw instruction
pub const WithdrawAccounts = struct {
    vault_token_account: sdk.AccountInfo,
    user_token_account: sdk.AccountInfo,
    owner: sdk.AccountInfo,
    token_program: sdk.AccountInfo,
    bump: u8,
};

/// Validate and parse withdraw accounts
pub fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!WithdrawAccounts {
    // Expect: vault_token_account, user_token_account, owner, token_program
    if (accounts.len < 4) {
        sdk.logMsg("Error: Not enough accounts for withdraw");
        return error.NotEnoughAccountKeys;
    }

    const vault_token_account = accounts[0];
    const user_token_account = accounts[1];
    const owner = accounts[2];
    const token_program = accounts[3];

    // Validate owner must sign the transaction
    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    var token_program_id: sdk.Pubkey = undefined;
    sdk.token.getTokenProgramId(&token_program_id);

    // Validate token program ID
    if (!sdk.pubkeyEq(token_program.key(), &token_program_id)) {
        sdk.logMsg("Error: Invalid token program");
        return error.IncorrectProgramId;
    }

    // Validate vault token account is owned by Token Program
    if (!sdk.pubkeyEq(vault_token_account.owner(), &token_program_id)) {
        sdk.logMsg("Error: Vault token account must be owned by Token Program");
        return error.IncorrectProgramId;
    }

    // Verify vault token account is the correct PDA for this owner and get bump seed
    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);

    if (!sdk.pubkeyEq(vault_token_account.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault token account PDA");
        return error.IncorrectProgramId;
    }

    return WithdrawAccounts{
        .vault_token_account = vault_token_account,
        .user_token_account = user_token_account,
        .owner = owner,
        .token_program = token_program,
        .bump = bump,
    };
}

/// Process withdraw instruction
pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
) sdk.ProgramResult {
    sdk.logMsg("Withdraw: Starting");

    // Validate accounts
    const validated = try validateAccounts(accounts, program_id);

    sdk.logMsg("Withdraw: Validated accounts");

    // Read vault token account to get balance
    const vault_account = try sdk.token.TokenAccount.fromAccountInfo(validated.vault_token_account);
    const amount = vault_account.amount();

    sdk.logMsg("Withdraw amount:");
    sdk.logU64(amount);

    // Validate vault has tokens to withdraw
    if (amount == 0) {
        sdk.logMsg("Error: Vault is empty");
        return error.InsufficientFunds;
    }

    // Create signer seeds for PDA signing
    const seed_owner = validated.owner.key().*;
    const bump_array = [_]u8{validated.bump};
    const signer_seeds = &[_][]const u8{
        "vault",
        seed_owner[0..],
        bump_array[0..],
    };

    // Execute transfer with PDA signature using the high-level wrapper
    try sdk.token.transfer.transferSigned(
        validated.vault_token_account,
        validated.user_token_account,
        validated.vault_token_account, // PDA is the authority
        amount,
        signer_seeds,
    );

    sdk.logMsg("Withdraw: Transfer completed successfully");
}
