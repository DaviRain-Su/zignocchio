# Agent.md — Zignocchio AI Agent Guide

> **Purpose**: This document is the canonical onboarding guide for AI agents working on the Zignocchio project. If you are an agent, read this file in its entirety before making any changes. All answers to "how do I..." should be derivable from this doc or the inline source comments.

## 1. What is Zignocchio?

Zignocchio is a **Solana sBPF SDK written in Zig** (targeting Zig 0.16.0). It provides:

- A minimal, safe SDK for writing Solana on-chain programs in Zig
- A TypeScript client package (`@zignocchio/client`) for building transactions and testing
- A CLI (`zignocchio-cli`) for scaffolding new programs
- Educational examples: `hello`, `counter`, `vault`, `transfer-sol`, `pda-storage`, `token-vault`, `escrow`

## 2. Directory Map

| Path | Purpose |
|------|---------|
| `sdk/` | Core Zig SDK. Start with `sdk/zignocchio.zig` |
| `sdk/guard.zig` | Security assertions (signer, owner, PDA, etc.) |
| `sdk/schema.zig` | Account data serialization / deserialization |
| `sdk/idioms.zig` | Common patterns (close account, read u64 LE) |
| `sdk/system.zig` | System Program CPI helpers |
| `sdk/token/` | SPL Token CPI helpers (transfer, ata, close_account) |
| `examples/` | One directory per educational example |
| `examples/{name}/lib.zig` | Example program entrypoint |
| `examples/{name}.test.ts` or `examples/{name}/{name}.test.ts` | Surfpool integration tests |
| `tests_litesvm/` | Litesvm-based integration tests (preferred) |
| `client/` | `@zignocchio/client` npm package |
| `client/src/litesvm.ts` | v1 → `@solana/kit` adapter for litesvm |
| `cli/` | `zignocchio-cli` source |
| `docs/` | Human-readable architecture and planning docs |
| `AGENTS.md` | Domain-specific rules (guards, anti-patterns) |
| `sdk/anti_patterns.md` | Vulnerability checklist |

## 3. Build & Test Commands

```bash
# Build an example program (produces zig-out/lib/{example_name}.so)
zig build -Dexample=hello

# Run Zig unit tests
zig build test

# Run all litesvm integration tests
npx jest tests_litesvm

# Run a specific test suite
npx jest tests_litesvm/vault.litesvm.test.ts

# Run surfpool tests (legacy, still maintained)
npx jest examples/vault.test.ts

# Build CLI
zig build -Dexample=cli   # or cd cli && zig build
```

**Critical**: Jest must run with `maxWorkers: 1` because litesvm returns `BigInt` values that crash Jest worker IPC serialization. This is already set in `jest.config.js`.

## 4. Architecture Decisions You Must Know

### 4.1 Per-example `.so` outputs
Each example builds to `zig-out/lib/{example_name}.so`. Previously all examples built to `program_name.so`, which caused stale artifact bugs. **Never hardcode `program_name.so`**.

### 4.2 Testing stack
- **Preferred**: `litesvm` (in-process, fast, uses `@solana/kit` v6.8.0)
- **Legacy**: `surfpool` (out-of-process validator, uses `@solana/web3.js` v1)
- When writing new tests, default to litesvm in `tests_litesvm/`.

### 4.3 Client adapter pattern
`client/src/litesvm.ts` bridges v1 `@solana/web3.js` to litesvm's `@solana/kit` API:
- `startLitesvm()` → returns `{ svm: LiteSVM, payer: Keypair }`
- `deployProgramToLitesvm(svm, { exampleName })` → builds and loads `.so`
- `sendTransaction(svm, payer, instructions, signers?)` → sends v1-style TX
- `getAccount()` / `setAccount()` / `airdrop()` → v1 PublicKey wrappers

Account role mapping in the adapter:
- readonly, not signer → 0
- writable, not signer → 1
- readonly, signer → 2
- writable, signer → 3

## 5. Agent Decision Trees

### If you need to add a new example program
1. Create `examples/{name}/lib.zig`
2. Add entry to `build.zig` example selector comment (if not already present)
3. Write `tests_litesvm/{name}.litesvm.test.ts`
4. Optionally write `examples/{name}.test.ts` for surfpool
5. Update `examples/README.md` learning path

### If you need to modify the SDK
1. Edit the relevant `sdk/*.zig` file
2. Add/update inline doc comments
3. Add unit tests in the same file or in `zig build test`
4. Run `zig build test` to verify
5. Run at least one litesvm test that exercises the changed API

### If you need to fix a failing litesvm test
1. Check if the `.so` is stale: `zig build -Dexample={name}` manually
2. Check account role mapping (signer/writable flags)
3. Check if accounts need to be pre-created with `setAccount`
4. Check for `BigInt` serialization issues (Jest worker crash)
5. For Token tests, ensure `svm.withDefaultPrograms()` is called

### If you need to write a CPI instruction
1. **Never** use module-scope `const` for Program IDs (see sBPF Traps)
2. Use `sdk.system.*` or `sdk.token.*` helpers when available
3. Release all `RefMut` / `Ref` borrows before calling `sdk.invoke` / `sdk.invokeSigned`
4. Validate accounts with `sdk.guard` assertions first

## 6. sBPF Traps — The Things That Will Break

These are non-obvious Zig 0.16 + sBPF v2 limitations. Violating any of them causes runtime crashes or compile failures.

| Trap | Rule | Example Fix |
|------|------|-------------|
| Module-scope const addresses | Zig places module-scope `const` arrays at invalid low addresses (0x0) causing access violations | Copy to a local `var` before taking `&` |
| Aggregate returns | sBPF does not support returning structs by value | Use output parameters (`*Pubkey`, `*u8`) |
| Zero-fill with `.**` | `.{0} ** 32` emits illegal BPF instructions | Use explicit loops or `std.mem.set` |
| `@alignCast` on unaligned data | Access violation at runtime | Use byte-wise `std.mem.readInt` / `writeInt` |
| `.rodata` string stripping | String literals may be stripped by `sbpf-linker` | Inline as stack arrays if needed |

### Module-scope const example
```zig
// WRONG — access violation
// const SYSTEM_PROGRAM_ID: Pubkey = .{0} ** 32;
// if (!sdk.pubkeyEq(account.owner(), &SYSTEM_PROGRAM_ID)) { ... }

// CORRECT — stack copy
var system_program_id: sdk.Pubkey = .{0} ** 32;
if (!sdk.pubkeyEq(account.owner(), &system_program_id)) { ... }
```

## 7. Security Guard Checklist

Before any state-mutating instruction completes, verify in this order:

1. `sdk.guard.assert_signer(account)`
2. `sdk.guard.assert_writable(account)` (for mutable accounts)
3. `sdk.guard.assert_owner(account, program_id)`
4. `sdk.guard.assert_pda(account, seeds, program_id, bump)` (for PDAs)
5. `sdk.guard.assert_discriminator(data, expected)` (for typed accounts)
6. `sdk.guard.assert_initialized(data)` / `assert_uninitialized(data)`
7. `sdk.guard.assert_min_data_len(account, len)`

See `AGENTS.md` and `sdk/anti_patterns.md` for the full checklist with examples.

## 8. Code Style Conventions

- Use `extern struct` for account data layouts (not auto-layout `struct`)
- Discriminators are `u8` and are the first byte of account data / instruction data
- PDA seeds use ASCII string literals (e.g., `"vault"`) followed by pubkeys as needed
- Functions that can fail return `sdk.ProgramResult` (an alias for `!void`)
- All log messages are ASCII strings passed to `sdk.logMsg()`
- When logging numbers, use `sdk.logU64(value)`

## 9. How to Read This Codebase

1. **New to the SDK?** Read `sdk/zignocchio.zig` top-to-bottom. It re-exports everything.
2. **New to examples?** Read in this order:
   - `examples/hello/lib.zig` — entrypoint, logging
   - `examples/counter/lib.zig` — account data mutation
   - `examples/vault/lib.zig` — PDA + System CPI
   - `examples/token-vault/lib.zig` — Token CPI
   - `examples/escrow/lib.zig` — full security flow
3. **New to testing?** Read `tests_litesvm/vault.litesvm.test.ts` as the canonical example.

## 10. Questions?

If this doc and the inline comments do not answer your question, check `AGENTS.md` and `sdk/anti_patterns.md`. Only open external documentation as a last resort.
