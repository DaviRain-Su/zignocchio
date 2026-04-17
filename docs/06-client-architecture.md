> 状态：Draft
> 日期：2026-04-15
> 版本：v1.0

* * *

## 1. 文档范围

本文档定义 `@zignocchio/client` npm 包的架构设计，目标是为 Zignocchio 合约提供一套与 Zig 端语义对齐的 TypeScript 客户端工具，覆盖 surfpool 测试、PDA 推导、账户布局类型映射、交易构建四个核心场景。

---

## 2. 设计原则

- **零隐藏成本**：不重新实现 RPC 或钱包逻辑，直接依赖 `@solana/web3.js`
- **与 Zig 端语义对齐**：PDA 种子规则、`AccountSchema` 布局、discriminator 顺序必须与合约端一致
- **树摇友好 (Tree-shakeable)**：按功能子路径导出，如 `@zignocchio/client/pda`
- **测试优先**：所有 API 的设计出发点都是简化 surfpool 集成测试

---

## 3. 包结构

```
client/
├── package.json
├── tsconfig.json
├── jest.config.js
├── src/
│   ├── index.ts              # 总入口，导出所有公共 API
│   ├── pda.ts                # PDA 推导工具
│   ├── layout.ts             # 账户布局类型与序列化
│   ├── instruction.ts        # 交易构建 helpers
│   ├── surfpool.ts           # surfpool 测试环境封装
│   └── types.ts              # 公共类型定义
├── tests/
│   ├── pda.test.ts
│   ├── layout.test.ts
│   ├── instruction.test.ts
│   └── surfpool.test.ts
└── README.md
```

---

## 4. 模块设计

### 4.1 `surfpool.ts` — 测试环境封装

**目标**：消除每个测试文件中重复的 surfpool 启动、程序部署、账户空投样板代码。

**核心类型**
```typescript
export interface SurfpoolContext {
  connection: Connection;
  validator: ChildProcess;
  payer: Keypair;
}

export interface DeployOptions {
  programPath: string;
  programId?: Keypair;  // 默认生成
}
```

**核心函数**
```typescript
export async function startSurfpool(): Promise<SurfpoolContext>;
export async function deployProgram(
  connection: Connection,
  opts: DeployOptions
): Promise<PublicKey>;
export async function stopSurfpool(ctx: SurfpoolContext): Promise<void>;
```

**使用示例**
```typescript
let ctx: SurfpoolContext;
let programId: PublicKey;

beforeAll(async () => {
  ctx = await startSurfpool();
  programId = await deployProgram(ctx.connection, {
    programPath: path.join(__dirname, '../zig-out/lib/hello.so'),
  });
});

afterAll(async () => {
  await stopSurfpool(ctx);
});
```

---

### 4.2 `pda.ts` — PDA 推导工具

**目标**：与 Zig 端 `sdk.findProgramAddress` 的种子规则完全对齐。

Zig 端种子类型：
- `[]const u8` 字符串字面量 → `Buffer.from(string)`
- `Pubkey` (32 bytes) → `pubkey.toBuffer()`
- `u8` bump → `Buffer.from([bump])`

**核心函数**
```typescript
export type PdaSeed = string | Buffer | Uint8Array;

export function findProgramAddress(
  seeds: PdaSeed[],
  programId: PublicKey
): [PublicKey, number];
```

**使用示例**
```typescript
const [escrowPda] = findProgramAddress(
  [Buffer.from('escrow'), maker.publicKey.toBuffer()],
  programId
);
```

---

### 4.3 `layout.ts` — 账户布局类型与序列化

**目标**：为 `extern struct` 提供 TypeScript 类型映射和轻量级序列化/反序列化。

**设计决策**：
- 不引入 `@solana/buffer-layout` 等重型依赖
- 使用纯 TypeScript 接口 + `Buffer` 读写函数
- 支持 `u8`, `u64`, `Pubkey` 三种核心类型

**核心类型**
```typescript
export type FieldType = 'u8' | 'u64' | 'pubkey';

export interface FieldDef {
  name: string;
  type: FieldType;
}

export interface LayoutSchema {
  discriminator?: number;
  fields: FieldDef[];
}
```

**核心函数**
```typescript
export function serializeLayout(schema: LayoutSchema, values: Record<string, any>): Buffer;
export function deserializeLayout(schema: LayoutSchema, data: Buffer): Record<string, any>;
export function layoutSize(schema: LayoutSchema): number;
```

**使用示例**
```typescript
const EscrowState = {
  discriminator: 0xAB,
  fields: [
    { name: 'discriminator', type: 'u8' },
    { name: 'maker', type: 'pubkey' },
    { name: 'taker', type: 'pubkey' },
    { name: 'amount', type: 'u64' },
  ],
} as const;

const data = serializeLayout(EscrowState, {
  discriminator: 0xAB,
  maker: maker.publicKey,
  taker: taker.publicKey,
  amount: 100_000_000n,
});
```

**对齐规则**
| Zig 类型 | TS 映射 | 大小 | 对齐 |
|---------|---------|------|------|
| `u8` | `number` | 1 | 1 |
| `u64` | `bigint` | 8 | 8 |
| `Pubkey` | `PublicKey` | 32 | 1 |

> 注意：Zignocchio 使用 `extern struct`，字段按声明顺序紧密排列，无额外填充（当前所有字段类型大小都是对齐大小的整数倍，因此天然对齐）。

---

### 4.4 `instruction.ts` — 交易构建 helpers

**目标**：简化 `TransactionInstruction` 和 `Transaction` 的构建，尤其是 account meta 的排序和 signer 注入。

**核心类型**
```typescript
export interface AccountMetaLike {
  pubkey: PublicKey;
  isSigner?: boolean;
  isWritable?: boolean;
}
```

**核心函数**
```typescript
export function buildInstruction(
  programId: PublicKey,
  accounts: AccountMetaLike[],
  data?: Buffer
): TransactionInstruction;

export function buildTransaction(
  ...instructions: TransactionInstruction[]
): Transaction;
```

**使用示例**
```typescript
const ix = buildInstruction(programId, [
  { pubkey: maker.publicKey, isSigner: true, isWritable: true },
  { pubkey: escrowPda, isWritable: true },
  { pubkey: SystemProgram.programId },
], data);

const tx = buildTransaction(ix);
await sendAndConfirmTransaction(connection, tx, [maker]);
```

---

## 5. 导出策略

**主入口** (`src/index.ts`)
```typescript
export * from './pda';
export * from './layout';
export * from './instruction';
export * from './surfpool';
export * from './types';
```

**子路径入口** (package.json `exports`)
```json
{
  "exports": {
    ".": "./dist/index.js",
    "./pda": "./dist/pda.js",
    "./layout": "./dist/layout.js",
    "./instruction": "./dist/instruction.js",
    "./surfpool": "./dist/surfpool.js"
  }
}
```

---

## 6. 依赖策略

**`dependencies`**：无（peer 依赖 `@solana/web3.js`）

**`peerDependencies`**
```json
{
  "@solana/web3.js": "^1.95.0"
}
```

**`devDependencies`**
```json
{
  "@solana/web3.js": "^1.95.0",
  "@types/jest": "^29.5.0",
  "jest": "^29.7.0",
  "ts-jest": "^29.1.0",
  "typescript": "^5.0.0"
}
```

---

## 7. 测试策略

- **单元测试**：`pda.ts`, `layout.ts`, `instruction.ts` 使用纯函数，可在 host 上直接测试
- **集成测试**：`surfpool.ts` 需要本地安装 `surfpool`，测试部署和生命周期管理
- **对齐测试**：`layout.ts` 的序列化结果必须与 Zig 端 `extern struct` 内存布局字节级一致

---

## 8. 发布流程

1. `npm run build` — `tsc` 编译到 `dist/`
2. `npm test` — 跑完全部测试
3. `npm run publish:local` — `npm pack` 验证包内容
4. `npm publish` — 发布到 npm registry（可选，由维护者执行）

---

## 9. 验收标准

- [ ] `package.json` + `tsconfig.json` 配置正确
- [ ] `src/index.ts` 导出所有公共 API
- [ ] `pda.ts` 的 `findProgramAddress` 与 Zig 端种子规则对齐
- [ ] `layout.ts` 支持 `u8` / `u64` / `pubkey` 序列化/反序列化
- [ ] `instruction.ts` 简化 TransactionInstruction 构建
- [ ] `surfpool.ts` 封装 surfpool 启动、部署、清理
- [ ] 单元测试覆盖所有纯函数模块
- [ ] README.md 包含安装说明和快速开始示例
