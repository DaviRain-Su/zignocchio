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
pub const Signer = accountWrapper(.signer, null);

/// Writable account declaration marker.
pub const WritableAccount = accountWrapper(.writable, null);

/// Read-only account declaration marker.
///
/// Runtime accounts marked writable are rejected with `error.ImmutableAccount`
/// so handlers cannot accidentally accept a mutable account through a readonly
/// declaration.
pub const ReadonlyAccount = accountWrapper(.readonly, null);

/// Executable program account declaration marker.
pub const ProgramAccount = accountWrapper(.program, null);

/// Executable program account declaration marker with a required program id.
pub fn ProgramAccountWithId(comptime expected_program_id: types.Pubkey) type {
    return accountWrapper(.program, expected_program_id);
}

fn accountWrapper(comptime kind: AccountWrapperKind, comptime expected_program_id: ?types.Pubkey) type {
    if (kind == .writable) {
        return struct {
            pub const zignocchio_framework_account_wrapper = kind;

            account: types.AccountInfo,

            /// Access the account public key.
            pub fn key(self: @This()) *const types.Pubkey {
                return self.account.key();
            }

            /// Access the account owner.
            pub fn owner(self: @This()) *const types.Pubkey {
                return self.account.owner();
            }

            /// Observe whether the account signed the transaction.
            pub fn isSigner(self: @This()) bool {
                return self.account.isSigner();
            }

            /// Observe whether the account was marked writable.
            pub fn isWritable(self: @This()) bool {
                return self.account.isWritable();
            }

            /// Observe whether the account is executable.
            pub fn executable(self: @This()) bool {
                return self.account.executable();
            }

            /// Get the current account data length.
            pub fn dataLen(self: @This()) usize {
                return self.account.dataLen();
            }

            /// Get the current lamport balance.
            pub fn lamports(self: @This()) u64 {
                return self.account.lamports();
            }

            /// Borrow account data immutably via the existing RAII API.
            pub fn tryBorrowData(self: @This()) errors.ProgramError!types.Ref([]const u8) {
                return self.account.tryBorrowData();
            }

            /// Borrow lamports immutably via the existing RAII API.
            pub fn tryBorrowLamports(self: @This()) errors.ProgramError!types.Ref(*const u64) {
                return self.account.tryBorrowLamports();
            }

            /// Borrow account data mutably via the existing RAII API.
            pub fn tryBorrowMutData(self: @This()) errors.ProgramError!types.RefMut([]u8) {
                return self.account.tryBorrowMutData();
            }

            /// Borrow lamports mutably via the existing RAII API.
            pub fn tryBorrowMutLamports(self: @This()) errors.ProgramError!types.RefMut(*u64) {
                return self.account.tryBorrowMutLamports();
            }
        };
    }

    return struct {
        pub const zignocchio_framework_account_wrapper = kind;
        pub const zignocchio_framework_expected_program_id = expected_program_id;

        account_addr: usize,
        key_ptr: *const types.Pubkey,
        owner_ptr: *const types.Pubkey,
        is_signer: bool,
        is_writable: bool,
        is_executable: bool,

        fn accountInfo(self: @This()) types.AccountInfo {
            const raw: *types.Account = @ptrFromInt(self.account_addr);
            return .{ .raw = raw };
        }

        /// Access the account public key without exposing mutation-capable APIs.
        pub fn key(self: @This()) *const types.Pubkey {
            return self.key_ptr;
        }

        /// Access the account owner without exposing mutation-capable APIs.
        pub fn owner(self: @This()) *const types.Pubkey {
            return self.owner_ptr;
        }

        /// Observe whether the account signed the transaction.
        pub fn isSigner(self: @This()) bool {
            return self.is_signer;
        }

        /// Observe whether the account was marked writable.
        pub fn isWritable(self: @This()) bool {
            return self.is_writable;
        }

        /// Observe whether the account is executable.
        pub fn executable(self: @This()) bool {
            return self.is_executable;
        }

        /// Get the current account data length.
        pub fn dataLen(self: @This()) usize {
            return self.accountInfo().dataLen();
        }

        /// Get the current lamport balance.
        pub fn lamports(self: @This()) u64 {
            return self.accountInfo().lamports();
        }

        /// Borrow account data immutably via the existing RAII API.
        pub fn tryBorrowData(self: @This()) errors.ProgramError!types.Ref([]const u8) {
            return self.accountInfo().tryBorrowData();
        }

        /// Borrow lamports immutably via the existing RAII API.
        pub fn tryBorrowLamports(self: @This()) errors.ProgramError!types.Ref(*const u64) {
            return self.accountInfo().tryBorrowLamports();
        }
    };
}

/// Typed instruction context for a reflected Accounts declaration.
pub fn Context(comptime Accounts: type) type {
    validateAccountsType(Accounts);

    return struct {
        pub const AccountsType = Accounts;

        /// Reflected runtime accounts bound in the Accounts declaration order.
        accounts: Accounts,
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

    var bound: Accounts = undefined;
    inline for (fields, 0..) |field, account_index| {
        @field(bound, field.name) = try bindAccountField(field.type, accounts[account_index]);
    }

    return .{ .accounts = bound };
}

fn bindAccountField(comptime Field: type, account: types.AccountInfo) errors.ProgramError!Field {
    if (Field == types.AccountInfo) {
        return account;
    }

    const kind = comptime accountWrapperKind(Field) orelse
        @compileError("unsupported account field type `" ++ @typeName(Field) ++ "`");

    switch (kind) {
        .signer => if (!account.isSigner()) {
            return error.MissingRequiredSignature;
        },
        .writable => if (!account.isWritable()) {
            return error.ImmutableAccount;
        },
        .readonly => if (account.isWritable()) {
            return error.ImmutableAccount;
        },
        .program => {
            if (!account.executable()) {
                return error.InvalidArgument;
            }
            if (comptime expectedProgramId(Field)) |expected| {
                var expected_key = expected;
                if (!types.pubkeyEq(account.key(), &expected_key)) {
                    return error.IncorrectProgramId;
                }
            }
        },
    }

    if (kind == .writable) {
        return .{ .account = account };
    }

    return .{
        .account_addr = @intFromPtr(account.raw),
        .key_ptr = account.key(),
        .owner_ptr = account.owner(),
        .is_signer = account.isSigner(),
        .is_writable = account.isWritable(),
        .is_executable = account.executable(),
    };
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
                if (field.is_comptime) {
                    @compileError("unsupported comptime account field `" ++ field.name ++ "` in `" ++ @typeName(Accounts) ++ "`");
                }
                validateAccountFieldType(field.type, Accounts);
            }
        },
        else => @compileError("Context requires a struct Accounts type"),
    }
}

fn validateAccountFieldType(comptime Field: type, comptime Accounts: type) void {
    if (Field == types.AccountInfo) return;
    if (accountWrapperKind(Field) != null) return;

    @compileError("unsupported account field type `" ++ @typeName(Field) ++ "` in `" ++ @typeName(Accounts) ++ "`");
}

fn accountWrapperKind(comptime Field: type) ?AccountWrapperKind {
    switch (@typeInfo(Field)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => {},
        else => return null,
    }

    if (!@hasDecl(Field, "zignocchio_framework_account_wrapper")) {
        return null;
    }

    const marker = Field.zignocchio_framework_account_wrapper;
    if (@TypeOf(marker) != AccountWrapperKind) {
        @compileError("invalid account wrapper declaration `" ++ @typeName(Field) ++ "`; use sdk.Signer, sdk.WritableAccount, sdk.ReadonlyAccount, or sdk.ProgramAccount");
    }

    return marker;
}

fn expectedProgramId(comptime Field: type) ?types.Pubkey {
    if (!@hasDecl(Field, "zignocchio_framework_expected_program_id")) {
        return null;
    }

    const expected = Field.zignocchio_framework_expected_program_id;
    if (@TypeOf(expected) != ?types.Pubkey) {
        @compileError("invalid ProgramAccount expected program id declaration");
    }

    return expected;
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

fn testAccount(comptime key_byte: u8, comptime is_signer: bool, comptime is_writable: bool, comptime is_executable: bool) types.Account {
    return .{
        .borrow_state = types.NON_DUP_MARKER,
        .is_signer = if (is_signer) 1 else 0,
        .is_writable = if (is_writable) 1 else 0,
        .executable = if (is_executable) 1 else 0,
        .resize_delta = 0,
        .key = .{key_byte} ** 32,
        .owner = .{0x42} ** 32,
        .lamports = 0,
        .data_len = 0,
    };
}

const TestAccountWithData = extern struct {
    account: types.Account,
    data: [8]u8,
};

fn testAccountWithData(comptime key_byte: u8, comptime is_signer: bool, comptime is_writable: bool, comptime is_executable: bool) TestAccountWithData {
    var account = testAccount(key_byte, is_signer, is_writable, is_executable);
    account.lamports = 123;
    account.data_len = 8;
    return .{
        .account = account,
        .data = .{ 0, 1, 2, 3, 4, 5, 6, 7 },
    };
}

fn expectAccountKeyByte(account: types.AccountInfo, expected: u8) !void {
    try std.testing.expectEqual(expected, account.key()[0]);
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

const NeedsSignerAccounts = struct {
    signer: Signer,
    raw: types.AccountInfo,
};

var account_context_handler_calls: usize = 0;
var wrapper_validation_handler_calls: usize = 0;

fn accountContextHandler(_: Context(NeedsSignerAccounts), _: []const u8) errors.ProgramResult {
    account_context_handler_calls += 1;
    return {};
}

const AccountContextProgram = struct {
    pub const Instruction = .{
        .{
            .name = "needs_signer",
            .accounts = NeedsSignerAccounts,
            .handler = accountContextHandler,
        },
    };
};

const NeedsWritableAccounts = struct {
    writable: WritableAccount,
};

const NeedsReadonlyAccounts = struct {
    readonly: ReadonlyAccount,
};

const NeedsProgramAccounts = struct {
    program: ProgramAccount,
};

fn writableValidationHandler(_: Context(NeedsWritableAccounts), _: []const u8) errors.ProgramResult {
    wrapper_validation_handler_calls += 1;
    return {};
}

fn readonlyValidationHandler(_: Context(NeedsReadonlyAccounts), _: []const u8) errors.ProgramResult {
    wrapper_validation_handler_calls += 1;
    return {};
}

fn programValidationHandler(_: Context(NeedsProgramAccounts), _: []const u8) errors.ProgramResult {
    wrapper_validation_handler_calls += 1;
    return {};
}

const WritableValidationProgram = struct {
    pub const Instruction = .{
        .{
            .name = "needs_writable",
            .accounts = NeedsWritableAccounts,
            .handler = writableValidationHandler,
        },
    };
};

const ReadonlyValidationProgram = struct {
    pub const Instruction = .{
        .{
            .name = "needs_readonly",
            .accounts = NeedsReadonlyAccounts,
            .handler = readonlyValidationHandler,
        },
    };
};

const ProgramValidationProgram = struct {
    pub const Instruction = .{
        .{
            .name = "needs_program",
            .accounts = NeedsProgramAccounts,
            .handler = programValidationHandler,
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
        expected_program: ProgramAccountWithId(.{0x21} ** 32),
        raw: types.AccountInfo,
    };

    const Ctx = Context(Accounts);
    try std.testing.expect(Ctx.AccountsType == Accounts);
}

test "Context binds plain account fields in declaration order" {
    const Accounts = struct {
        zed_name_first: types.AccountInfo,
        alpha_name_second: types.AccountInfo,
        middle_name_third: types.AccountInfo,
    };

    var raw0 = testAccount(1, false, false, false);
    var raw1 = testAccount(2, false, false, false);
    var raw2 = testAccount(3, false, false, false);
    var runtime_accounts = [_]types.AccountInfo{
        .{ .raw = &raw0 },
        .{ .raw = &raw1 },
        .{ .raw = &raw2 },
    };

    const ctx = try buildContext(Accounts, runtime_accounts[0..]);

    try expectAccountKeyByte(ctx.accounts.zed_name_first, 1);
    try expectAccountKeyByte(ctx.accounts.alpha_name_second, 2);
    try expectAccountKeyByte(ctx.accounts.middle_name_third, 3);
}

test "Context ignores surplus accounts after binding declared fields" {
    const Accounts = struct {
        declared: types.AccountInfo,
    };

    var raw0 = testAccount(4, false, false, false);
    var raw1 = testAccount(5, false, false, false);
    var runtime_accounts = [_]types.AccountInfo{
        .{ .raw = &raw0 },
        .{ .raw = &raw1 },
    };

    const ctx = try buildContext(Accounts, runtime_accounts[0..]);

    try expectAccountKeyByte(ctx.accounts.declared, 4);
}

test "Context empty accounts accepts zero and surplus runtime accounts" {
    var no_accounts: [0]types.AccountInfo = .{};
    const empty_ctx = try buildContext(EmptyAccounts, no_accounts[0..]);
    _ = empty_ctx.accounts;

    var raw0 = testAccount(6, false, false, false);
    var runtime_accounts = [_]types.AccountInfo{.{ .raw = &raw0 }};
    const surplus_ctx = try buildContext(EmptyAccounts, runtime_accounts[0..]);
    _ = surplus_ctx.accounts;
}

test "Context checks account count before wrapper validation and handler execution" {
    account_context_handler_calls = 0;
    var raw0 = testAccount(7, false, false, false);
    var underfilled_accounts = [_]types.AccountInfo{.{ .raw = &raw0 }};
    const data = instructionDiscriminator("needs_signer");

    try expectProgramError(error.NotEnoughAccountKeys, dispatch(AccountContextProgram, underfilled_accounts[0..], &data));

    try std.testing.expectEqual(@as(usize, 0), account_context_handler_calls);
}

test "Context wrapper validation runs before handler execution" {
    account_context_handler_calls = 0;
    var raw0 = testAccount(8, false, false, false);
    var raw1 = testAccount(9, false, false, false);
    var runtime_accounts = [_]types.AccountInfo{
        .{ .raw = &raw0 },
        .{ .raw = &raw1 },
    };
    const data = instructionDiscriminator("needs_signer");

    try expectProgramError(error.MissingRequiredSignature, dispatch(AccountContextProgram, runtime_accounts[0..], &data));

    try std.testing.expectEqual(@as(usize, 0), account_context_handler_calls);
}

test "Context binds wrapper fields to their ordinal accounts after validation" {
    const Accounts = struct {
        signer: Signer,
        writable: WritableAccount,
        readonly: ReadonlyAccount,
        program: ProgramAccount,
    };

    var raw0 = testAccount(10, true, false, false);
    var raw1 = testAccount(11, false, true, false);
    var raw2 = testAccount(12, false, false, false);
    var raw3 = testAccount(13, false, false, true);
    var runtime_accounts = [_]types.AccountInfo{
        .{ .raw = &raw0 },
        .{ .raw = &raw1 },
        .{ .raw = &raw2 },
        .{ .raw = &raw3 },
    };

    const ctx = try buildContext(Accounts, runtime_accounts[0..]);

    try std.testing.expectEqual(@as(u8, 10), ctx.accounts.signer.key()[0]);
    try std.testing.expectEqual(@as(u8, 11), ctx.accounts.writable.key()[0]);
    try std.testing.expectEqual(@as(u8, 12), ctx.accounts.readonly.key()[0]);
    try std.testing.expectEqual(@as(u8, 13), ctx.accounts.program.key()[0]);
}

test "Signer validates signatures and exposes readonly-safe accessors" {
    var backing = testAccountWithData(14, true, false, false);
    const signer = try bindAccountField(Signer, .{ .raw = &backing.account });

    try std.testing.expectEqual(@as(u8, 14), signer.key()[0]);
    try std.testing.expectEqual(@as(u8, 0x42), signer.owner()[0]);
    try std.testing.expect(signer.isSigner());
    try std.testing.expect(!signer.isWritable());
    try std.testing.expect(!signer.executable());
    try std.testing.expectEqual(@as(usize, 8), signer.dataLen());
    try std.testing.expectEqual(@as(u64, 123), signer.lamports());

    var data_ref = try signer.tryBorrowData();
    try std.testing.expectEqual(@as(u8, 0), data_ref.value[0]);
    data_ref.release();

    var lamports_ref = try signer.tryBorrowLamports();
    try std.testing.expectEqual(@as(u64, 123), lamports_ref.value.*);
    lamports_ref.release();

    try std.testing.expect(!@hasDecl(Signer, "tryBorrowMutData"));
    try std.testing.expect(!@hasDecl(Signer, "tryBorrowMutLamports"));

    var not_signer = testAccount(15, false, false, false);
    try std.testing.expectError(error.MissingRequiredSignature, bindAccountField(Signer, .{ .raw = &not_signer }));
}

test "WritableAccount validates writable and delegates mutable borrows" {
    var backing = testAccountWithData(16, false, true, false);
    const writable = try bindAccountField(WritableAccount, .{ .raw = &backing.account });

    try std.testing.expectEqual(@as(u8, 16), writable.key()[0]);
    try std.testing.expect(writable.isWritable());
    try std.testing.expectEqual(@as(usize, 8), writable.dataLen());
    try std.testing.expectEqual(@as(u64, 123), writable.lamports());

    var data_ref = try writable.tryBorrowMutData();
    data_ref.value[0] = 99;
    try std.testing.expectError(error.AccountBorrowFailed, writable.tryBorrowMutData());
    data_ref.release();

    var data_ref_after_release = try writable.tryBorrowData();
    try std.testing.expectEqual(@as(u8, 99), data_ref_after_release.value[0]);
    data_ref_after_release.release();

    var lamports_ref = try writable.tryBorrowMutLamports();
    lamports_ref.value.* += 7;
    try std.testing.expectError(error.AccountBorrowFailed, writable.tryBorrowMutLamports());
    lamports_ref.release();
    try std.testing.expectEqual(@as(u64, 130), backing.account.lamports);

    var not_writable = testAccount(17, false, false, false);
    try std.testing.expectError(error.ImmutableAccount, bindAccountField(WritableAccount, .{ .raw = &not_writable }));
}

test "ReadonlyAccount rejects writable inputs and exposes immutable borrows only" {
    var backing = testAccountWithData(18, false, false, false);
    const readonly = try bindAccountField(ReadonlyAccount, .{ .raw = &backing.account });

    try std.testing.expectEqual(@as(u8, 18), readonly.key()[0]);
    try std.testing.expect(!readonly.isWritable());
    try std.testing.expectEqual(@as(usize, 8), readonly.dataLen());
    try std.testing.expectEqual(@as(u64, 123), readonly.lamports());

    var data_ref = try readonly.tryBorrowData();
    try std.testing.expectEqual(@as(u8, 0), data_ref.value[0]);
    data_ref.release();

    var lamports_ref = try readonly.tryBorrowLamports();
    try std.testing.expectEqual(@as(u64, 123), lamports_ref.value.*);
    lamports_ref.release();

    try std.testing.expect(!@hasDecl(ReadonlyAccount, "tryBorrowMutData"));
    try std.testing.expect(!@hasDecl(ReadonlyAccount, "tryBorrowMutLamports"));
    try std.testing.expect(!@hasField(ReadonlyAccount, "account"));

    var writable_input = testAccount(19, false, true, false);
    try std.testing.expectError(error.ImmutableAccount, bindAccountField(ReadonlyAccount, .{ .raw = &writable_input }));
}

test "ProgramAccount validates executable accounts and expected ids" {
    var executable = testAccount(20, false, false, true);
    const program = try bindAccountField(ProgramAccount, .{ .raw = &executable });

    try std.testing.expectEqual(@as(u8, 20), program.key()[0]);
    try std.testing.expect(program.executable());
    try std.testing.expect(!@hasDecl(ProgramAccount, "tryBorrowMutData"));
    try std.testing.expect(!@hasDecl(ProgramAccount, "tryBorrowMutLamports"));
    try std.testing.expect(!@hasField(ProgramAccount, "account"));

    var not_executable = testAccount(21, false, false, false);
    try std.testing.expectError(error.InvalidArgument, bindAccountField(ProgramAccount, .{ .raw = &not_executable }));

    const ExpectedProgram = ProgramAccountWithId(.{22} ** 32);
    var matching = testAccount(22, false, false, true);
    _ = try bindAccountField(ExpectedProgram, .{ .raw = &matching });

    var wrong = testAccount(23, false, false, true);
    try std.testing.expectError(error.IncorrectProgramId, bindAccountField(ExpectedProgram, .{ .raw = &wrong }));
}

test "wrapper validation failures prevent handler execution for writable readonly and program accounts" {
    wrapper_validation_handler_calls = 0;

    var invalid_writable = testAccount(24, false, false, false);
    var writable_accounts = [_]types.AccountInfo{.{ .raw = &invalid_writable }};
    const writable_data = instructionDiscriminator("needs_writable");
    try expectProgramError(error.ImmutableAccount, dispatch(WritableValidationProgram, writable_accounts[0..], &writable_data));
    try std.testing.expectEqual(@as(usize, 0), wrapper_validation_handler_calls);

    var invalid_readonly = testAccount(25, false, true, false);
    var readonly_accounts = [_]types.AccountInfo{.{ .raw = &invalid_readonly }};
    const readonly_data = instructionDiscriminator("needs_readonly");
    try expectProgramError(error.ImmutableAccount, dispatch(ReadonlyValidationProgram, readonly_accounts[0..], &readonly_data));
    try std.testing.expectEqual(@as(usize, 0), wrapper_validation_handler_calls);

    var invalid_program = testAccount(26, false, false, false);
    var program_accounts = [_]types.AccountInfo{.{ .raw = &invalid_program }};
    const program_data = instructionDiscriminator("needs_program");
    try expectProgramError(error.InvalidArgument, dispatch(ProgramValidationProgram, program_accounts[0..], &program_data));
    try std.testing.expectEqual(@as(usize, 0), wrapper_validation_handler_calls);
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
