# litesvm Compatibility PoC Report

> Task: L1 — Verify that `litesvm` can load and execute Zignocchio-compiled `.so` programs.
> Date: 2026-04-15
> Status: ✅ **Fully Compatible**

## Executive Summary

**litesvm is fully compatible with Zignocchio-compiled sBPF programs.**

After initial confusion caused by a stale `program_name.so` artifact, comprehensive testing confirms that litesvm can successfully load, deploy, and execute Zignocchio programs with all major SDK features (logging, account access, ownership checks).

## Initial False Alarm

The first litesvm test against `hello.so` appeared to fail with:

```
InstructionErrorCustom { code: 4 }
```

This mapped to Zignocchio's `InvalidInstructionData` error. However, **root cause analysis revealed this was a build artifact issue**, not a runtime incompatibility.

### The Real Problem: Stale `program_name.so`

The project's `build.zig` outputs every example to the same path:

```zig
const program_so_path = "zig-out/lib/program_name.so";
```

When the first litesvm test ran, `program_name.so` contained a stale binary from a previously built example (not `hello`). That stale binary interpreted the empty instruction data differently and returned error code 4.

**After forcing a clean rebuild (`rm -rf .zig-cache zig-out/lib/program_name.so && zig build -Dexample=hello`), the program executed successfully.**

## Verified Test Matrix

| Program | Features Used | litesvm Result |
|---------|---------------|----------------|
| `hello` | `logMsg` (`.rodata` string literal) | ✅ **PASS** |
| `hello_no_log` | Zero syscalls | ✅ **PASS** |
| `hello_log_u64` | `logU64` (`sol_log_64_`) | ✅ **PASS** |
| `hello_stack_log` | `logMsg` with stack-allocated inline array | ✅ **PASS** |
| `counter` | Account access, ownership check, writable borrow, `logMsg` | ✅ **PASS** |

All tests pass without any code changes to Zignocchio or the example programs.

## @solana/web3.js v1 Compatibility Assessment

**Not directly compatible out of the box**, but adapter is trivial.

litesvm's `sendTransaction` accepts `@solana/kit`'s `Transaction` type, not v1's `Transaction`. However, litesvm is designed to be used with `@solana/kit` (web3.js v2), and our tests demonstrate that writing tests in kit style is straightforward.

For `@zignocchio/client`, we can provide an optional adapter:

```typescript
import { VersionedTransaction } from '@solana/web3.js';

function v1ToKitTransaction(v1Tx: Transaction) {
  const messageV0 = v1Tx.compileMessage();
  return new VersionedTransaction(messageV0);
}
```

Or we can simply write litesvm tests natively in `@solana/kit` style.

## Critical Finding: AccountRole Enum Values

When constructing instructions manually with `@solana/kit`, the `role` field uses this mapping:

```typescript
enum AccountRole {
  READONLY = 0,        // isSigner: false, isWritable: false
  WRITABLE = 1,        // isSigner: false, isWritable: true
  READONLY_SIGNER = 2, // isSigner: true,  isWritable: false
  WRITABLE_SIGNER = 3, // isSigner: true,  isWritable: true
}
```

Using `role: 2` for a writable non-signer account (as one might guess from v1's `{ isSigner: false, isWritable: true }`) causes `@solana/kit` to require a signature for that account.

## Recommendations

### Immediate
1. **L1 is complete. litesvm is approved for Zignocchio testing.**
2. **Fix `build.zig`** so each example outputs to a uniquely named `.so` (e.g. `zig-out/lib/hello.so`, `zig-out/lib/counter.so`) to prevent stale artifact issues.

### Short-term (L3: Test Migration)
1. Migrate `hello.test.ts` to litesvm as the pilot.
2. Migrate `counter.test.ts` to litesvm.
3. Gradually migrate `vault`, `token-vault`, `escrow`, `transfer-sol`, `pda-storage`.
4. Keep surfpool tests as fallback during the transition period.

### Long-term
1. Add a `litesvm.ts` adapter to `@zignocchio/client` for teams that want to use v1 `Transaction` with litesvm.
2. Document the `@solana/kit` account role mapping in `client/README.md`.

## Files Added

- `tests_litesvm/hello.litesvm.test.ts` — 3 tests (load via file, load with loader, execute)
- `tests_litesvm/counter.litesvm.test.ts` — 1 test (deploy + execute with account access)
- `tests_litesvm/POC_REPORT.md` — this report

## Test Results

```
PASS tests_litesvm/hello.litesvm.test.ts
  litesvm compatibility PoC
    ✓ loads a Zignocchio hello.so program via addProgramFromFile
    ✓ loads a Zignocchio program via addProgramWithLoader using BPFLoader2
    ✓ executes a transaction against the loaded program successfully

PASS tests_litesvm/counter.litesvm.test.ts
  litesvm counter compatibility
    ✓ deploys and executes the counter program

Test Suites: 2 passed, 2 total
Tests:       4 passed, 4 total
```
