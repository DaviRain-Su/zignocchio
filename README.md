# Solana Programs with Zig + sbpf-linker

Build Solana programs in Zig using the standard BPF target and [sbpf-linker](https://github.com/blueshift-gg/sbpf-linker).

## Features

- ✅ Uses standard Zig BPF target (no custom forks)
- ✅ Zero external dependencies
- ✅ **Zignocchio SDK** - Full-featured Zig SDK for Solana
- ✅ Anchor-like comptime framework with generated dispatch and typed contexts
- ✅ Anchor-compatible instruction discriminators: `sha256("global:<instruction_name>")[0..8]`
- ✅ Deterministic IDL generation from framework program declarations
- ✅ LLVM bitcode generation via `-femit-llvm-bc`
- ✅ Direct syscall invocation via function pointers
- ✅ Auto-generated syscall bindings with MurmurHash3
- ✅ Automated build pipeline with `zig build`
- ✅ Jest/litesvm, surfpool, and Rust mollusk-svm test coverage

## Prerequisites

```bash
# Install sbpf-linker from master (includes latest fixes)
cargo install --git https://github.com/blueshift-gg/sbpf-linker.git

# Install Zig 0.16.0
# Install Node.js for testing
```

**Note:** SPL Token support requires [sbpf-linker PR #14](https://github.com/blueshift-gg/sbpf-linker/pull/14) to be merged (adds `.rodata.cst32` section support for 32-byte constants).

## Building

```bash
# Build the default example
zig build

# Build a specific example
zig build -Dexample=hello
```

This generates:
1. `entrypoint.bc` - LLVM bitcode from Zig source
2. `zig-out/lib/{example_name}.so` - Final Solana program (e.g., `zig-out/lib/hello.so`)

### IDL Generation

Framework examples can emit deterministic IDL JSON:

```bash
zig build -Dexample=hello idl
```

This writes `zig-out/idl/hello.json`. IDL fixtures include `examples/idl-metadata` and `examples/framework-accounts`.

## Testing

```bash
npm install
zig build test
npx tsc --noEmit
npx jest examples --testPathIgnorePatterns=surfpool --runInBand
cargo test --manifest-path tests_rust/Cargo.toml --test hello_mollusk
```

Tests will:
- Run Zig unit tests for the SDK and examples
- Type-check the TypeScript client and tests
- Exercise examples in litesvm and Rust mollusk-svm
- Cover legacy surfpool integration tests when run explicitly

## How It Works

### 1. Framework Dispatch

The public framework layer lives at `sdk/framework.zig` and is exported as `sdk.framework`, with top-level aliases for the most-used APIs:

```zig
const sdk = @import("sdk");

const Accounts = struct {};

pub const Program = struct {
    pub const max_accounts = 1;

    pub const Instruction = .{
        .{
            .name = "hello",
            .accounts = Accounts,
            .handler = hello,
            .allow_empty = true,
        },
    };
};

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.exportProgram(Program), .{input});
}

fn hello(_: sdk.Context(Accounts), _: []const u8) sdk.ProgramResult {
    sdk.logMsg("Hello from Zignocchio!");
    return {};
}
```

`sdk.exportProgram` generates the entrypoint dispatcher. Instruction data is routed by the Anchor-compatible discriminator from `sdk.instructionDiscriminator("hello")`; handlers can opt into empty-data compatibility with `.allow_empty = true`.

### 2. Typed Accounts

`sdk.Context(Accounts)` reflects an accounts declaration and binds runtime accounts in order. The first public wrappers are:

- `sdk.Signer`
- `sdk.WritableAccount`
- `sdk.ReadonlyAccount`
- `sdk.ProgramAccount`
- `sdk.framework.ProgramAccountWithId(expected_program_id)`
- raw `sdk.AccountInfo` for an escape hatch

`ReadonlyAccount`, `Signer`, and `ProgramAccount` expose metadata-only views. `WritableAccount` keeps the existing RAII borrow APIs for data and lamports.

### 3. Auto-Generated Syscall Bindings

All Solana syscalls are auto-generated from definitions using MurmurHash3-32:

```bash
zig run tools/gen_syscalls.zig -- sdk/syscalls.zig
```

This creates function pointers for all syscalls:

```zig
const syscalls = @import("syscalls.zig");
syscalls.log(&message);  // Calls sol_log_ with hash 0x207559bd
```

The hash `0x207559bd` is computed as `murmur3_32("sol_log_", 0)` and resolved by Solana VM at runtime via `call -0x1`.

### 4. Inline String Data

To prevent sbpf-linker from stripping .rodata, we inline string data:

```zig
const message = [_]u8{'H','e','l','l','o',' ','w','o','r','l','d','!'};
```

### 5. LLVM Bitcode Pipeline

sbpf-linker is an LTO compiler, not a traditional linker. It needs LLVM IR:

```bash
zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc
sbpf-linker --cpu v3 --export entrypoint -o program.so entrypoint.bc
```

## Zignocchio SDK

This project includes **Zignocchio**, a zero-dependency SDK for building Solana programs in Zig, inspired by [Pinocchio](https://github.com/anza-xyz/pinocchio).

### Quick Example

```zig
const sdk = @import("sdk");

const Accounts = struct {
    authority: sdk.Signer,
    state: sdk.WritableAccount,
};

fn update(ctx: sdk.Context(Accounts), _: []const u8) sdk.ProgramResult {
    if (!ctx.accounts.authority.isSigner()) return error.MissingRequiredSignature;

    const account = ctx.accounts.state;
    var data = try account.tryBorrowMutData();
    defer data.release();

    data.value[0] = 42;
    return .{};
}
```

### SDK Features

- **Zero-copy input deserialization** - Direct memory access to Solana's input buffer
- **RAII borrow tracking** - Safe mutable access with automatic cleanup
- **Comptime framework** - `exportProgram`, `Context`, typed account wrappers, and generated IDL
- **Type-safe API** - Strong typing for all Solana primitives
- **PDAs** - Program Derived Address functions
- **CPI** - Cross-program invocation support
- **Efficient** - Bit-packed borrow state, optimized syscalls

See the `//!` docs in [`sdk/zignocchio.zig`](sdk/zignocchio.zig), [`sdk/framework.zig`](sdk/framework.zig), and [`examples/`](examples/) for working programs.

## Project Structure

```
.
├── build.zig              # Automated build pipeline
├── build.zig.zon          # Zero dependencies
├── sdk/                   # Zignocchio SDK
│   ├── zignocchio.zig     # Main SDK module
│   ├── framework.zig      # Comptime framework, dispatch, typed contexts, IDL
│   ├── types.zig          # Core types (Pubkey, AccountInfo)
│   ├── entrypoint.zig     # Input deserialization
│   ├── syscalls.zig       # Auto-generated syscalls
│   ├── pda.zig            # Program Derived Addresses
│   ├── cpi.zig            # Cross-program invocation
│   ├── allocator.zig      # BumpAllocator
│   ├── log.zig            # Logging utilities
│   └── errors.zig         # Error types
├── examples/              # Example programs
│   ├── hello/             # Minimal framework example
│   ├── framework-accounts/# Framework account wrapper fixture
│   ├── idl-metadata/      # IDL metadata fixture
│   └── ...                # Counter, vault, token, escrow examples
├── tests_rust/            # Rust mollusk-svm tests
├── tests_litesvm/         # TypeScript litesvm helpers/tests
└── tools/
    ├── murmur3.zig        # MurmurHash3-32 implementation
    ├── syscall_defs.zig   # Syscall definitions
    └── gen_syscalls.zig   # Syscall generator
```

## License

MIT
