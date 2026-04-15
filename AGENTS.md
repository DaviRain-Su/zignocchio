# AGENTS.md — Zignocchio Agent Index

> **Last updated**: 2026-04-15  
> **Zig version**: 0.16.0  
> **Solana target**: sBPF v2

**This file is an INDEX only.** For detailed knowledge, read the inline doc comments in the source files listed below.

## Start Here

1. Read this index to understand the layout
2. Open the source file relevant to your task
3. Read the `//!` doc comments at the top of that file — they are canonical

## Directory Map

| Path | What to read for details |
|------|--------------------------|
| `sdk/zignocchio.zig` | SDK overview, quick start, upstream dependency map, feature matrix |
| `sdk/anti_patterns.zig` | Vulnerability checklist (17 anti-patterns + pre-submit checklist) |
| `sdk/guard.zig` | Security assertion API and usage examples |
| `sdk/schema.zig` | `AccountSchema` comptime interface |
| `sdk/idioms.zig` | Common patterns: close account, read/write u64 LE |
| `sdk/system.zig` | System Program CPI helpers |
| `sdk/token/mod.zig` | SPL Token Program CPI helpers |
| `sdk/memo.zig` | SPL Memo Program CPI helpers |
| `sdk/token_2022.zig` | SPL Token-2022 Program CPI helpers |
| `examples/hello/lib.zig` | Minimal entrypoint example |
| `examples/counter/lib.zig` | Account data mutation example |
| `examples/vault/lib.zig` | PDA + System CPI + signed CPI example |
| `examples/token-vault/lib.zig` | Token Program CPI example |
| `examples/escrow/lib.zig` | Full security flow example |
| `client/src/litesvm.ts` | v1 → `@solana/kit` adapter for litesvm tests |
| `examples/{name}/tests/litesvm.test.ts` | Litesvm TypeScript integration tests |
| `examples/{name}/tests/surfpool.test.ts` | Legacy surfpool TypeScript integration tests |
| `tests_rust/examples/{name}.rs` | Rust `mollusk-svm` tests that load Zig `.so` files |
| `docs/` | Human-readable PRD / architecture docs |

## Quick Commands

```bash
# Build an example
zig build -Dexample=hello

# Run Zig unit tests
zig build test

# Run all litesvm integration tests
npx jest examples --testPathIgnorePatterns='surfpool'

# Run Rust mollusk-svm tests
cd tests_rust && cargo test

# Run legacy surfpool tests
npx jest examples --testPathPattern='surfpool'
```

## Critical Rules (One-liners)

- **No module-scope `const` addresses** in BPF — copy to local `var` first. See `sdk/zignocchio.zig` → "Zig 0.16 BPF Pitfalls".
- **Release all borrows before CPI** — see `sdk/idioms.zig`.
- **Guard order**: signer → writable → owner → PDA → discriminator → initialized/uninitialized. See `sdk/guard.zig`.
- **Per-example `.so`**: outputs go to `zig-out/lib/{example_name}.so`. Never hardcode `program_name.so`.
- **Jest must use `maxWorkers: 1`** for litesvm — already set in `jest.config.js`.

## Learning Path

Study examples in this order:
1. `hello` — entrypoint and logging
2. `counter` — account data access and mutation
3. `vault` — PDAs, System CPI, security guards
4. `token-vault` — Token Program CPI
5. `escrow` — Full security flow

## Ecosystem Gap (vs Pinocchio Rust)

Zignocchio currently covers: `system`, `token`, `ata`, `memo`, `token-2022`.
Missing compared to full Pinocchio ecosystem: `pinocchio-log` advanced helpers, `pinocchio-pubkey` utilities, Token-2022 extension instructions (transfer fees, confidential transfers), and full ATA close helpers.
See `sdk/zignocchio.zig` module docs for the upstream dependency map.
