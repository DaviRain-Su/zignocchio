//! Make Instruction - Create an escrow account

const std = @import("std");
const sdk = @import("sdk");

pub const DISCRIMINATOR: u8 = 0;

pub const EscrowState = extern struct {
    pub const DISCRIMINATOR: u8 = 0xE5;

    discriminator: u8,
    maker: sdk.Pubkey,
    taker: sdk.Pubkey,
    amount: u64,
};

const MakeAccounts = struct {
    maker: sdk.AccountInfo,
    escrow: sdk.AccountInfo,
    system_program: sdk.AccountInfo,
};

const MakeData = struct {
    taker: sdk.Pubkey,
    amount: u64,
};

fn validateAccounts(
    accounts: []sdk.AccountInfo,
    program_id: *const sdk.Pubkey,
) sdk.ProgramError!MakeAccounts {
    if (accounts.len < 3) {
        sdk.logMsg("Error: Not enough accounts for make");
        return error.NotEnoughAccountKeys;
    }

    const maker = accounts[0];
    const escrow = accounts[1];
    const system_program = accounts[2];

    try sdk.guard.assert_signer(maker);
    try sdk.guard.assert_writable(escrow);

    // Escrow must be owned by system program (not yet created)
    var system_program_id: sdk.Pubkey = undefined;
    sdk.system.getSystemProgramId(&system_program_id);
    try sdk.guard.assert_owner(escrow, &system_program_id);

    // Escrow must be empty
    if (escrow.lamports() != 0) {
        sdk.logMsg("Error: Escrow must be empty");
        return error.AccountAlreadyInitialized;
    }

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

    // Verify system program
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    return MakeAccounts{
        .maker = maker,
        .escrow = escrow,
        .system_program = system_program,
    };
}

fn parseData(data: []const u8) sdk.ProgramError!MakeData {
    if (data.len != 40) {
        sdk.logMsg("Error: Invalid make data length");
        return error.InvalidInstructionData;
    }
    var taker: sdk.Pubkey = undefined;
    @memcpy(&taker, data[0..32]);
    const amount = std.mem.readInt(u64, data[32..40], .little);
    if (amount == 0) {
        sdk.logMsg("Error: Amount must be greater than 0");
        return error.InvalidInstructionData;
    }
    return MakeData{ .taker = taker, .amount = amount };
}

pub fn process(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Make: Starting");

    const validated = try validateAccounts(accounts, program_id);
    const data = try parseData(instruction_data);

    sdk.logMsg("Make: Validated accounts and data");
    sdk.logMsg("Make amount:");
    sdk.logU64(data.amount);

    const space: u64 = @sizeOf(EscrowState);
    // Rent exempt minimum for the escrow account data
    const rent_exempt = ((space / 256) + 1) * 6960;
    const lamports = data.amount + rent_exempt;

    // Create escrow account via CPI with PDA signing
    const maker_key = validated.maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);

    const signers_seeds = &[_][]const u8{
        "escrow",
        &maker_key,
        &[_]u8{bump},
    };

    try sdk.system.createAccountSigned(
        validated.maker,
        validated.escrow,
        program_id,
        space,
        lamports,
        signers_seeds,
    );

    sdk.logMsg("Make: Escrow account created");

    // Initialize escrow state
    const Schema = sdk.schema.AccountSchema(EscrowState);
    if (validated.escrow.dataLen() < Schema.LEN) {
        sdk.logMsg("Error: Escrow data too small");
        return error.AccountDataTooSmall;
    }

    const escrow_data = validated.escrow.borrowMutDataUnchecked();
    var state = Schema.from_bytes_unchecked(escrow_data);
    state.discriminator = EscrowState.DISCRIMINATOR;
    state.maker = validated.maker.key().*;
    state.taker = data.taker;
    state.amount = data.amount;

    sdk.logMsg("Make: Escrow initialized successfully");
}
