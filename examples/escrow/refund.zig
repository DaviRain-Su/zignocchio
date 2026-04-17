//! Refund Instruction - Maker refunds escrow and retrieves lamports

const sdk = @import("sdk");
const make = @import("make.zig");

pub const DISCRIMINATOR: u8 = 2;

const RefundAccounts = struct {
    maker: sdk.AccountInfo,
    escrow: sdk.AccountInfo,
};

fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!RefundAccounts {
    if (accounts.len < 2) {
        sdk.logMsg("Error: Not enough accounts for refund");
        return error.NotEnoughAccountKeys;
    }

    const maker = accounts[0];
    const escrow = accounts[1];

    try sdk.guard.assert_signer(maker);
    try sdk.guard.assert_writable(maker);
    try sdk.guard.assert_writable(escrow);

    // Escrow must be owned by this program
    try sdk.guard.assert_owner(escrow, program_id);

    // Verify escrow discriminator
    const Schema = sdk.schema.AccountSchema(make.EscrowState);
    try Schema.validate(escrow);

    // Verify escrow PDA belongs to maker (discover bump, don't hardcode 255)
    const maker_key = maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);
    if (!sdk.pubkeyEq(escrow.key(), &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }

    return RefundAccounts{
        .maker = maker,
        .escrow = escrow,
    };
}

pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
) sdk.ProgramResult {
    sdk.logMsg("Refund: Starting");

    const validated = try validateAccounts(accounts, program_id);

    // Read escrow amount
    const Schema = sdk.schema.AccountSchema(make.EscrowState);
    var ref: sdk.RefMut([]u8) = undefined;
    try Schema.from_bytes(validated.escrow, &ref);
    defer ref.release();
    const state = Schema.from_bytes_unchecked(ref.value);

    sdk.logMsg("Refund: Validated accounts");
    sdk.logMsg("Refund amount:");
    sdk.logU64(state.amount);

    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    // Use idioms.close_account to transfer all lamports back to maker
    // and clear the discriminator
    try sdk.idioms.close_account(validated.escrow, validated.maker);

    sdk.logMsg("Refund: Lamports refunded successfully");
}
