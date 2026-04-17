# AGENTS.md — Zignocchio Agent Index

> **Zig version**: 0.16.0
> **Solana target**: sBPF v2

**This file is an INDEX only.** For detailed knowledge, read the `//!` doc comments in the source files listed below.

## Directory Map

| Path | What to read for details |
|------|--------------------------|
| `sdk/zignocchio.zig` | SDK overview, quick start, upstream dependency map |
| `sdk/anti_patterns.zig` | Vulnerability checklist |
| `sdk/guard.zig` | Security assertion API |
| `sdk/schema.zig` | `AccountSchema` comptime interface |
| `sdk/idioms.zig` | Common patterns |
| `sdk/system.zig` | System Program CPI helpers |
| `sdk/token/mod.zig` | SPL Token Program CPI helpers |
| `sdk/token/ata.zig` | Associated Token Account CPI helpers |
| `sdk/token/instructions/` | SPL Token instruction builders |
| `sdk/memo.zig` | SPL Memo Program CPI helpers |
| `sdk/token_2022.zig` | SPL Token-2022 Program CPI helpers |
| `sdk/pda.zig` | PDA derivation and Pubkey helpers |
| `sdk/log.zig` | Syscall logging utilities |
| `examples/hello/lib.zig` | Minimal entrypoint example |
| `examples/counter/lib.zig` | Account data mutation example |
| `examples/vault/lib.zig` | PDA + System CPI example |
| `examples/transfer-sol/lib.zig` | Simple lamport transfer example |
| `examples/pda-storage/lib.zig` | PDA creation + data mutation example |
| `examples/token-vault/lib.zig` | Token Program CPI example |
| `examples/escrow/lib.zig` | Full security flow example |
| `client/src/litesvm.ts` | v1 → `@solana/kit` adapter |
| `examples/{name}/tests/` | TypeScript integration tests (litesvm + surfpool) |
| `tests_rust/examples/` | Rust `mollusk-svm` tests that load Zig `.so` files |
| `docs/` | PRD / architecture docs |

## Quick Commands

```bash
# Build an example
zig build -Dexample=hello

# Run Zig unit tests
zig build test

# Run litesvm integration tests
npx jest examples --testPathIgnorePatterns='surfpool'

# Run Rust mollusk-svm tests
cd tests_rust && cargo test

# Run legacy surfpool tests
npx jest examples --testPathPattern='surfpool'
```
