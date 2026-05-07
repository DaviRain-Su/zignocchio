//! Public comptime framework layer for Zignocchio programs.
//!
//! This module is intentionally additive: it builds on the existing low-level
//! entrypoint, AccountInfo, error, and guard APIs rather than replacing them.

const std = @import("std");
const errors = @import("errors.zig");
const entrypoint = @import("entrypoint.zig");
const types = @import("types.zig");

/// Marker value used by the first public account wrapper declarations.
const AccountWrapperKind = enum {
    signer,
    writable,
    readonly,
    program,
};

/// Signed account declaration marker.
pub const Signer = accountWrapper(.signer);

/// Writable account declaration marker.
pub const WritableAccount = accountWrapper(.writable);

/// Read-only account declaration marker.
pub const ReadonlyAccount = accountWrapper(.readonly);

/// Executable program account declaration marker.
pub const ProgramAccount = accountWrapper(.program);

fn accountWrapper(comptime kind: AccountWrapperKind) type {
    return struct {
        pub const zignocchio_framework_account_wrapper = kind;
    };
}

/// Typed instruction context for a reflected Accounts declaration.
pub fn Context(comptime Accounts: type) type {
    validateAccountsType(Accounts);

    return struct {
        pub const AccountsType = Accounts;
    };
}

/// Compute an Anchor-compatible instruction discriminator.
///
/// The discriminator is the first 8 bytes of:
/// `sha256("global:" ++ instruction_name)`.
pub fn instructionDiscriminator(comptime instruction_name: []const u8) [8]u8 {
    @setEvalBranchQuota(10_000);
    const preimage = "global:" ++ instruction_name;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &digest, .{});
    return digest[0..8].*;
}

/// Validate a framework Program declaration and return a Solana entrypoint.
///
/// The returned entrypoint uses the existing low-level input deserializer and
/// routes instructions by Anchor-compatible 8-byte discriminators.
pub fn exportProgram(comptime Program: type) fn ([*]u8) callconv(.c) u64 {
    validateProgram(Program);

    const max_accounts = if (@hasDecl(Program, "max_accounts"))
        Program.max_accounts
    else
        types.MAX_TX_ACCOUNTS;

    return entrypoint.entrypoint(max_accounts, struct {
        fn processInstruction(
            _: *const types.Pubkey,
            accounts: []types.AccountInfo,
            instruction_data: []const u8,
        ) errors.ProgramResult {
            return dispatch(Program, accounts, instruction_data);
        }
    }.processInstruction);
}

/// Dispatch instruction data for a framework Program declaration.
///
/// Empty instruction data is accepted only by an instruction that explicitly
/// declares `allow_empty = true`. Non-empty data shorter than 8 bytes and
/// unknown 8-byte discriminators fail deterministically with
/// `error.InvalidInstructionData`.
pub fn dispatch(
    comptime Program: type,
    accounts: []types.AccountInfo,
    instruction_data: []const u8,
) errors.ProgramResult {
    validateProgram(Program);

    const instructions = Program.Instruction;

    return dispatchInstructions(instructions, accounts, instruction_data);
}

fn validateProgram(comptime Program: type) void {
    switch (@typeInfo(Program)) {
        .@"struct" => {},
        else => @compileError("framework Program declaration requires a struct type"),
    }

    const instructions = if (@hasDecl(Program, "Instruction"))
        Program.Instruction
    else
        @compileError("framework Program declaration is missing `Instruction` declaration");

    validateInstructionDeclaration(instructions);
}

fn validateInstructionDeclaration(comptime instructions: anytype) void {
    const Instructions = @TypeOf(instructions);

    switch (@typeInfo(Instructions)) {
        .@"struct" => |struct_info| {
            comptime var empty_handlers: usize = 0;

            if (struct_info.is_tuple) {
                if (struct_info.fields.len == 0) {
                    @compileError("framework `Instruction` declaration must contain at least one instruction");
                }

                inline for (struct_info.fields) |field| {
                    const instruction = @field(instructions, field.name);
                    validateInstructionSpec(instruction);
                    if (comptime instructionAllowsEmpty(instruction)) {
                        empty_handlers += 1;
                    }
                }
            } else {
                validateInstructionSpec(instructions);
                if (comptime instructionAllowsEmpty(instructions)) {
                    empty_handlers += 1;
                }
            }

            if (empty_handlers > 1) {
                @compileError("framework Program declaration has multiple `allow_empty` instructions");
            }
        },
        else => @compileError("unsupported framework `Instruction` declaration; expected an instruction struct or tuple"),
    }
}

fn validateInstructionSpec(comptime instruction: anytype) void {
    const Instruction = @TypeOf(instruction);

    switch (@typeInfo(Instruction)) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                @compileError("unsupported framework instruction declaration; expected named fields `name`, `accounts`, and `handler`");
            }
        },
        else => @compileError("unsupported framework instruction declaration; expected named fields `name`, `accounts`, and `handler`"),
    }

    if (!@hasField(Instruction, "name")) {
        @compileError("framework instruction declaration is missing `name`");
    }
    if (!@hasField(Instruction, "accounts")) {
        @compileError("framework instruction declaration is missing `accounts`");
    }
    if (!@hasField(Instruction, "handler")) {
        @compileError("framework instruction declaration is missing `handler`");
    }
    if (@hasField(Instruction, "allow_empty") and @TypeOf(instruction.allow_empty) != bool) {
        @compileError("framework instruction `allow_empty` must be a bool");
    }

    if (!(comptime isStringLike(@TypeOf(instruction.name)))) {
        @compileError("framework instruction `name` must be a string literal or []const u8");
    }
    const name: []const u8 = instruction.name;
    if (name.len == 0) {
        @compileError("framework instruction `name` must not be empty");
    }

    if (@TypeOf(instruction.accounts) != type) {
        @compileError("framework instruction `accounts` must be an Accounts type");
    }
    validateAccountsType(instruction.accounts);

    validateHandler(instruction.handler, instruction.accounts);
}

fn dispatchInstructions(
    comptime instructions: anytype,
    accounts: []types.AccountInfo,
    instruction_data: []const u8,
) errors.ProgramResult {
    if (instruction_data.len == 0) {
        return dispatchEmpty(instructions, accounts, instruction_data);
    }

    if (instruction_data.len < 8) {
        return error.InvalidInstructionData;
    }

    const discriminator = instruction_data[0..8];
    const args = instruction_data[8..];
    return dispatchDiscriminator(instructions, accounts, discriminator, args);
}

fn dispatchEmpty(
    comptime instructions: anytype,
    accounts: []types.AccountInfo,
    instruction_data: []const u8,
) errors.ProgramResult {
    const Instructions = @TypeOf(instructions);
    const struct_info = @typeInfo(Instructions).@"struct";

    if (struct_info.is_tuple) {
        inline for (struct_info.fields) |field| {
            const instruction = @field(instructions, field.name);
            if (comptime instructionAllowsEmpty(instruction)) {
                return invokeInstruction(instruction, accounts, instruction_data);
            }
        }
    } else if (comptime instructionAllowsEmpty(instructions)) {
        return invokeInstruction(instructions, accounts, instruction_data);
    }

    return error.InvalidInstructionData;
}

fn dispatchDiscriminator(
    comptime instructions: anytype,
    accounts: []types.AccountInfo,
    discriminator: []const u8,
    args: []const u8,
) errors.ProgramResult {
    const Instructions = @TypeOf(instructions);
    const struct_info = @typeInfo(Instructions).@"struct";

    if (struct_info.is_tuple) {
        inline for (struct_info.fields) |field| {
            const instruction = @field(instructions, field.name);
            const expected = comptime instructionDiscriminator(instruction.name);
            if (std.mem.eql(u8, discriminator, &expected)) {
                return invokeInstruction(instruction, accounts, args);
            }
        }
    } else {
        const expected = comptime instructionDiscriminator(instructions.name);
        if (std.mem.eql(u8, discriminator, &expected)) {
            return invokeInstruction(instructions, accounts, args);
        }
    }

    return error.InvalidInstructionData;
}

fn invokeInstruction(
    comptime instruction: anytype,
    accounts: []types.AccountInfo,
    args: []const u8,
) errors.ProgramResult {
    const ctx = try buildContext(instruction.accounts, accounts);
    return @call(.always_inline, instruction.handler, .{ ctx, args });
}

fn buildContext(comptime Accounts: type, accounts: []types.AccountInfo) errors.ProgramError!Context(Accounts) {
    validateAccountsType(Accounts);
    const fields = @typeInfo(Accounts).@"struct".fields;
    if (accounts.len < fields.len) {
        return error.NotEnoughAccountKeys;
    }

    // Full reflected account binding is implemented by the account reflection
    // feature. The foundation dispatch layer needs a constructible context so
    // no-account programs such as hello can route through generated dispatch.
    return .{};
}

fn instructionAllowsEmpty(comptime instruction: anytype) bool {
    const Instruction = @TypeOf(instruction);
    if (!@hasField(Instruction, "allow_empty")) {
        return false;
    }
    return instruction.allow_empty;
}

fn validateAccountsType(comptime Accounts: type) void {
    switch (@typeInfo(Accounts)) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                @compileError("Context requires a named struct Accounts type");
            }

            inline for (struct_info.fields) |field| {
                if (!isSupportedAccountField(field.type)) {
                    @compileError("unsupported account field type `" ++ @typeName(field.type) ++ "` in `" ++ @typeName(Accounts) ++ "`");
                }
            }
        },
        else => @compileError("Context requires a struct Accounts type"),
    }
}

fn isSupportedAccountField(comptime Field: type) bool {
    if (Field == types.AccountInfo) return true;
    return @hasDecl(Field, "zignocchio_framework_account_wrapper");
}

fn validateHandler(comptime handler: anytype, comptime Accounts: type) void {
    const Handler = @TypeOf(handler);

    switch (@typeInfo(Handler)) {
        .@"fn" => |fn_info| validateHandlerFnInfo(fn_info, Accounts),
        .pointer => |ptr_info| {
            switch (@typeInfo(ptr_info.child)) {
                .@"fn" => |fn_info| validateHandlerFnInfo(fn_info, Accounts),
                else => @compileError("framework instruction `handler` must be a function"),
            }
        },
        else => @compileError("framework instruction `handler` must be a function"),
    }
}

fn validateHandlerFnInfo(comptime fn_info: anytype, comptime Accounts: type) void {
    if (fn_info.params.len != 2) {
        @compileError("framework instruction handler signature must be `fn (Context(Accounts), []const u8) sdk.ProgramResult`");
    }

    if (fn_info.params[0].type == null or fn_info.params[0].type.? != Context(Accounts)) {
        @compileError("framework instruction handler first parameter must be `Context(Accounts)`");
    }

    if (fn_info.params[1].type == null or fn_info.params[1].type.? != []const u8) {
        @compileError("framework instruction handler second parameter must be `[]const u8`");
    }

    if (fn_info.return_type == null or fn_info.return_type.? != errors.ProgramResult) {
        @compileError("framework instruction handler must return sdk.ProgramResult");
    }
}

fn isStringLike(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => ptr_info.child == u8,
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |array_info| array_info.child == u8,
                else => false,
            },
            .many, .c => ptr_info.child == u8,
        },
        else => false,
    };
}

const EmptyAccounts = struct {};

fn helloHandler(_: Context(EmptyAccounts), _: []const u8) errors.ProgramResult {
    return {};
}

var observed_handler: enum { none, hello, initialize, error_handler } = .none;
var observed_calls: usize = 0;
var observed_args_len: usize = 0;

fn observedHelloHandler(_: Context(EmptyAccounts), args: []const u8) errors.ProgramResult {
    observed_handler = .hello;
    observed_calls += 1;
    observed_args_len = args.len;
    return {};
}

fn observedInitializeHandler(_: Context(EmptyAccounts), args: []const u8) errors.ProgramResult {
    observed_handler = .initialize;
    observed_calls += 1;
    observed_args_len = args.len;
    return {};
}

fn observedErrorHandler(_: Context(EmptyAccounts), _: []const u8) errors.ProgramResult {
    observed_handler = .error_handler;
    observed_calls += 1;
    return error.IncorrectAuthority;
}

fn resetObservedDispatch() void {
    observed_handler = .none;
    observed_calls = 0;
    observed_args_len = 0;
}

fn expectProgramError(comptime expected: anyerror, result: errors.ProgramResult) !void {
    if (result) {
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expectEqual(expected, err);
    }
}

const MinimalProgram = struct {
    pub const Instruction = .{
        .{
            .name = "hello",
            .accounts = EmptyAccounts,
            .handler = helloHandler,
        },
    };
};

const EmptyCompatibleProgram = struct {
    pub const Instruction = .{
        .{
            .name = "hello",
            .accounts = EmptyAccounts,
            .handler = observedHelloHandler,
            .allow_empty = true,
        },
    };
};

const MultiInstructionProgram = struct {
    pub const Instruction = .{
        .{
            .name = "hello",
            .accounts = EmptyAccounts,
            .handler = observedHelloHandler,
        },
        .{
            .name = "initialize",
            .accounts = EmptyAccounts,
            .handler = observedInitializeHandler,
        },
    };
};

const ErrorProgram = struct {
    pub const Instruction = .{
        .{
            .name = "fail",
            .accounts = EmptyAccounts,
            .handler = observedErrorHandler,
        },
    };
};

test "instructionDiscriminator matches Anchor known vectors" {
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x95, 0x76, 0x3b, 0xdc, 0xc4, 0x7f, 0xa1, 0xb3 }, &instructionDiscriminator("hello"));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xaf, 0xaf, 0x6d, 0x1f, 0x0d, 0x98, 0x9b, 0xed }, &instructionDiscriminator("initialize"));
}

test "instructionDiscriminator is comptime deterministic and table-safe" {
    const first = comptime instructionDiscriminator("hello");
    const second = comptime instructionDiscriminator("hello");
    try std.testing.expectEqualSlices(u8, &first, &second);

    const StaticDispatchMetadata = struct {
        pub const entries = [_]struct {
            name: []const u8,
            discriminator: [8]u8,
        }{
            .{ .name = "hello", .discriminator = instructionDiscriminator("hello") },
            .{ .name = "initialize", .discriminator = instructionDiscriminator("initialize") },
        };
    };

    try std.testing.expectEqualSlices(u8, &instructionDiscriminator("hello"), &StaticDispatchMetadata.entries[0].discriminator);
}

test "instructionDiscriminator preserves exact public instruction names" {
    const lower = instructionDiscriminator("initialize");
    const upper = instructionDiscriminator("Initialize");
    const snake = instructionDiscriminator("hello_world");
    const camel = instructionDiscriminator("helloWorld");

    try std.testing.expect(!std.mem.eql(u8, &lower, &upper));
    try std.testing.expect(!std.mem.eql(u8, &snake, &camel));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x91, 0x30, 0xc7, 0x0c, 0xeb, 0x73, 0xfc, 0xf8 }, &upper);
}

test "minimal public Program declarations compile" {
    comptime validateProgram(MinimalProgram);

    const entry = comptime exportProgram(MinimalProgram);
    _ = entry;
}

test "Context accepts first public account wrapper declarations" {
    const Accounts = struct {
        signer: Signer,
        writable: WritableAccount,
        readonly: ReadonlyAccount,
        program: ProgramAccount,
        raw: types.AccountInfo,
    };

    const Ctx = Context(Accounts);
    try std.testing.expect(Ctx.AccountsType == Accounts);
}

test "matching discriminator dispatches to exactly one handler" {
    resetObservedDispatch();
    var accounts: [0]types.AccountInfo = .{};
    var data = instructionDiscriminator("hello") ++ [_]u8{ 0xaa, 0xbb };

    try dispatch(MultiInstructionProgram, accounts[0..], &data);

    try std.testing.expectEqual(.hello, observed_handler);
    try std.testing.expectEqual(@as(usize, 1), observed_calls);
    try std.testing.expectEqual(@as(usize, 2), observed_args_len);
}

test "unknown discriminator fails without executing a handler" {
    resetObservedDispatch();
    var accounts: [0]types.AccountInfo = .{};
    const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };

    try expectProgramError(error.InvalidInstructionData, dispatch(MultiInstructionProgram, accounts[0..], &data));

    try std.testing.expectEqual(.none, observed_handler);
    try std.testing.expectEqual(@as(usize, 0), observed_calls);
}

test "truncated non-empty discriminator fails safely" {
    var accounts: [0]types.AccountInfo = .{};
    const full = instructionDiscriminator("hello");

    for (1..8) |len| {
        resetObservedDispatch();
        try expectProgramError(error.InvalidInstructionData, dispatch(MultiInstructionProgram, accounts[0..], full[0..len]));
        try std.testing.expectEqual(.none, observed_handler);
        try std.testing.expectEqual(@as(usize, 0), observed_calls);
    }
}

test "multi-instruction dispatch routes unambiguously" {
    var accounts: [0]types.AccountInfo = .{};
    const hello_data = instructionDiscriminator("hello");
    const initialize_data = instructionDiscriminator("initialize");

    resetObservedDispatch();
    try dispatch(MultiInstructionProgram, accounts[0..], &hello_data);
    try std.testing.expectEqual(.hello, observed_handler);
    try std.testing.expectEqual(@as(usize, 1), observed_calls);

    resetObservedDispatch();
    try dispatch(MultiInstructionProgram, accounts[0..], &initialize_data);
    try std.testing.expectEqual(.initialize, observed_handler);
    try std.testing.expectEqual(@as(usize, 1), observed_calls);
}

test "generic empty instruction data policy is deterministic" {
    resetObservedDispatch();
    var accounts: [0]types.AccountInfo = .{};

    try expectProgramError(error.InvalidInstructionData, dispatch(MultiInstructionProgram, accounts[0..], ""));

    try std.testing.expectEqual(.none, observed_handler);
    try std.testing.expectEqual(@as(usize, 0), observed_calls);
}

test "explicit empty compatibility path invokes selected handler" {
    resetObservedDispatch();
    var accounts: [0]types.AccountInfo = .{};

    try dispatch(EmptyCompatibleProgram, accounts[0..], "");

    try std.testing.expectEqual(.hello, observed_handler);
    try std.testing.expectEqual(@as(usize, 1), observed_calls);
    try std.testing.expectEqual(@as(usize, 0), observed_args_len);
}

test "handler errors propagate unchanged" {
    resetObservedDispatch();
    var accounts: [0]types.AccountInfo = .{};
    const data = instructionDiscriminator("fail");

    try expectProgramError(error.IncorrectAuthority, dispatch(ErrorProgram, accounts[0..], &data));

    try std.testing.expectEqual(.error_handler, observed_handler);
    try std.testing.expectEqual(@as(usize, 1), observed_calls);
}
