# @zignocchio/client

TypeScript client helpers for [Zignocchio](https://github.com/davirain/zignocchio) — a zero-dependency Zig SDK for Solana programs.

## Overview

This package provides lightweight, tree-shakeable utilities that align with Zignocchio's on-chain semantics:

- **PDA derivation** matching Zig `findProgramAddress` seed rules
- **Account layout** serialization/deserialization aligned with `extern struct`
- **Transaction building** helpers for instruction data and account metas
- **Surfpool testing** lifecycle management (start, deploy, stop)

## Installation

```bash
npm install @zignocchio/client
```

Peer dependency:

```bash
npm install @solana/web3.js
```

## Quick Start

```typescript
import { Connection, Keypair, PublicKey } from '@solana/web3.js';
import {
  startSurfpool,
  deployProgram,
  stopSurfpool,
  findProgramAddress,
  serializeLayout,
  buildInstruction,
  buildTransaction,
} from '@zignocchio/client';

let ctx = await startSurfpool();
let programId = await deployProgram(ctx.connection, {
  programPath: './zig-out/lib/hello.so',
});

// Derive PDA (matches Zig seed rules)
const [counterPda] = findProgramAddress(
  [Buffer.from('counter'), payer.publicKey.toBuffer()],
  programId
);

// Serialize instruction data
const data = serializeLayout(
  {
    discriminator: 0x01,
    fields: [
      { name: 'discriminator', type: 'u8' },
      { name: 'amount', type: 'u64' },
    ],
  },
  { discriminator: 0x01, amount: 100n }
);

// Build and send transaction
const ix = buildInstruction(programId, [
  { pubkey: payer.publicKey, isSigner: true, isWritable: true },
  { pubkey: counterPda, isWritable: true },
], data);

const tx = buildTransaction(ix);
// await sendAndConfirmTransaction(ctx.connection, tx, [payer]);

await stopSurfpool(ctx);
```

## API Reference

### PDA Derivation

```typescript
import { findProgramAddress } from '@zignocchio/client/pda';

const [pda, bump] = findProgramAddress(
  ['escrow', makerPublicKey.toBuffer()],
  programId
);
```

Seeds accept `string`, `Buffer`, or `Uint8Array`, matching Zig `[]const u8` semantics.

### Account Layout

```typescript
import { serializeLayout, deserializeLayout, layoutSize } from '@zignocchio/client/layout';

const schema = {
  discriminator: 0xAB,
  fields: [
    { name: 'discriminator', type: 'u8' },
    { name: 'owner', type: 'pubkey' },
    { name: 'count', type: 'u64' },
  ],
} as const;

const data = serializeLayout(schema, { discriminator: 0xAB, owner: pk, count: 42n });
const parsed = deserializeLayout(schema, data);
```

Supported field types:

| Type | TS Type | Size |
|------|---------|------|
| `u8` | `number` | 1 byte |
| `u64` | `bigint` | 8 bytes, little-endian |
| `pubkey` | `PublicKey` | 32 bytes |

### Transaction Building

```typescript
import { buildInstruction, buildTransaction } from '@zignocchio/client/instruction';

const ix = buildInstruction(programId, [
  { pubkey: userKey, isSigner: true, isWritable: true },
  { pubkey: vaultKey, isWritable: true },
]);

const tx = buildTransaction(ix);
```

### Surfpool Testing

```typescript
import { startSurfpool, deployProgram, stopSurfpool } from '@zignocchio/client/surfpool';

const ctx = await startSurfpool();
const programId = await deployProgram(ctx.connection, { programPath: '...' });
// ... run tests ...
await stopSurfpool(ctx);
```

## Development

```bash
cd client
npm install
npm run build
npm test
```

## License

MIT
