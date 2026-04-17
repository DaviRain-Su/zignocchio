//! Accept Instruction - Taker accepts escrow and receives lamports

const sdk = @import("sdk");
const make = @import("make.zig");

pub const DISCRIMINATOR: u8 = 1;

const AcceptAccounts = struct {
    taker: sdk.AccountInfo,
    escrow: sdk.AccountInfo,
    maker: sdk.AccountInfo,
};

fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!AcceptAccounts {
    if (accounts.len < 3) {
        sdk.logMsg("Error: Not enough accounts for accept");
        return error.NotEnoughAccountKeys;
    }

    const taker = accounts[0];
    const escrow = accounts[1];
    const maker = accounts[2];

    try sdk.guard.assert_signer(taker);
    try sdk.guard.assert_writable(taker);
    try sdk.guard.assert_writable(escrow);

    // Escrow must be owned by this program
    try sdk.guard.assert_owner(escrow, program_id);

    // Verify escrow discriminator
    const Schema = sdk.schema.AccountSchema(make.EscrowState);
    try Schema.validate(escrow);

    // Verify escrow PDA (discover bump, don't hardcode 255)
    const maker_key = maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);
    if (!sdk.pubkeyEq(escrow.key(), &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }

    // Read state to check taker restriction
    var ref: sdk.RefMut([]u8) = undefined;
    try Schema.from_bytes(escrow, &ref);
    defer ref.release();

    // If taker is specified (not all zeros), only that taker can accept
    const zero_pubkey: sdk.Pubkey = .{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
    var taker_key: sdk.Pubkey = undefined;
    @memcpy(&taker_key, ref.value[33..65]);

    var is_zero = true;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        if (taker_key[i] != zero_pubkey[i]) {
            is_zero = false;
            break;
        }
    }

    if (!is_zero) {
        var is_authorized = true;
        i = 0;
        while (i < 32) : (i += 1) {
            if (taker.key()[i] != taker_key[i]) {
                is_authorized = false;
                break;
            }
        }
        if (!is_authorized) {
            sdk.logMsg("Error: Unauthorized taker");
            return error.IncorrectAuthority;
        }
    }

    return AcceptAccounts{
        .taker = taker,
        .escrow = escrow,
        .maker = maker,
    };
}

pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
) sdk.ProgramResult {
    sdk.logMsg("Accept: Starting");

    const validated = try validateAccounts(accounts, program_id);

    // Read escrow amount
    const Schema = sdk.schema.AccountSchema(make.EscrowState);
    var ref: sdk.RefMut([]u8) = undefined;
    try Schema.from_bytes(validated.escrow, &ref);
    defer ref.release();
    const state = Schema.from_bytes_unchecked(ref.value);

    sdk.logMsg("Accept: Validated accounts");
    sdk.logMsg("Accept amount:");
    sdk.logU64(state.amount);

    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    // Transfer lamports from escrow to taker using direct modification
    // (same transaction, so direct lamport transfer is valid)
    var escrow_lamports = try validated.escrow.tryBorrowMutLamports();
    defer escrow_lamports.release();

    var taker_lamports = try validated.taker.tryBorrowMutLamports();
    defer taker_lamports.release();

    const amount = escrow_lamports.value.*;
    escrow_lamports.value.* = 0;
    taker_lamports.value.* += amount;

    // Clear discriminator and close account data
    var data = validated.escrow.borrowMutDataUnchecked();
    if (data.len > 0) {
        data[0] = 0;
    }

    sdk.logMsg("Accept: Lamports transferred successfully");
}
