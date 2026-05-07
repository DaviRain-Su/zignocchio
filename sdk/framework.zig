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
    const preimage = "global:" ++ instruction_name;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &digest, .{});
    return digest[0..8].*;
}

/// Validate a framework Program declaration and return a Solana entrypoint.
///
/// Full discriminator dispatch is implemented by the framework dispatch
/// feature. This foundation API validates the public declaration surface and
/// returns a generated entrypoint shell using the existing low-level
/// deserializer.
pub fn exportProgram(comptime Program: type) fn ([*]u8) callconv(.c) u64 {
    validateProgram(Program);

    const max_accounts = if (@hasDecl(Program, "max_accounts"))
        Program.max_accounts
    else
        types.MAX_TX_ACCOUNTS;

    return entrypoint.entrypoint(max_accounts, struct {
        fn processInstruction(
            _: *const types.Pubkey,
            _: []types.AccountInfo,
            _: []const u8,
        ) errors.ProgramResult {
            return error.InvalidInstructionData;
        }
    }.processInstruction);
}

fn validateProgram(comptime Program: type) void {
    switch (@typeInfo(Program)) {
        .@"struct" => {},
        else => @compileError("framework Program declaration requires a struct type"),
    }

    const instructions = if (@hasDecl(Program, "Instruction"))
        Program.Instruction
    else if (@hasDecl(Program, "instructions"))
        Program.instructions
    else
        @compileError("framework Program declaration is missing `Instruction` declaration");

    validateInstructionDeclaration(instructions);
}

fn validateInstructionDeclaration(comptime instructions: anytype) void {
    const Instructions = @TypeOf(instructions);

    switch (@typeInfo(Instructions)) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                if (struct_info.fields.len == 0) {
                    @compileError("framework `Instruction` declaration must contain at least one instruction");
                }

                inline for (struct_info.fields) |field| {
                    validateInstructionSpec(@field(instructions, field.name));
                }
            } else {
                validateInstructionSpec(instructions);
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

    if (!isStringLike(@TypeOf(instruction.name))) {
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
            .slice => ptr_info.child == u8 and ptr_info.is_const,
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |array_info| array_info.child == u8 and ptr_info.is_const,
                else => false,
            },
            else => false,
        },
        else => false,
    };
}

const EmptyAccounts = struct {};

fn helloHandler(_: Context(EmptyAccounts), _: []const u8) errors.ProgramResult {
    return {};
}

fn initializeHandler(_: Context(EmptyAccounts), _: []const u8) errors.ProgramResult {
    return {};
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

const LowercaseInitializeProgram = struct {
    pub const instructions = .{
        .{
            .name = "initialize",
            .accounts = EmptyAccounts,
            .handler = initializeHandler,
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
    comptime validateProgram(LowercaseInitializeProgram);

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
