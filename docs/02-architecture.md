> 状态：Draft
> 日期：2026-04-15
> 版本：v1.0

* * *

## 1. 架构目标

Zignocchio 采用**三层架构**：

1. **运行时层（Runtime）** — 已完成。零依赖的 Solana BPF 运行时抽象。
2. **约束层（Guard + Schema）** — 待建。编译期与运行期结合的安全检查机制。
3. **知识层（Knowledge）** — 待建。内嵌在源码 doc comments 中的结构化知识。

核心设计原则：
- **Zero dependencies**：不引入任何外部 crate / npm / zig 包依赖
- **Agent-readable**：所有复杂度对 agent 可见，无隐藏宏魔法
- **Compile-time verification**：优先用 Zig `comptime` 做静态约束
- **Code + Knowledge合一**：知识写在 `.zig` 文件的 doc comments 中，`zig build test` 自动验证

---

## 2. 系统边界

```
┌─────────────────────────────────────────────────────────────────┐
│                        AI Code Agent                            │
│  (Claude Code / Codex / Cursor / Kimi / ser9-kimi ...)          │
└─────────────────────────┬───────────────────────────────────────┘
                          │ reads doc comments + API
┌─────────────────────────▼───────────────────────────────────────┐
│                        Zignocchio SDK                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Runtime   │  │   Guard     │  │   AccountSchema         │  │
│  │   (done)    │  │   (new)     │  │   (new)                 │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   System    │  │   Idioms    │  │   Anti-patterns /       │  │
│  │   CPI       │  │   (new)     │  │   AGENTS.md (new)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────┘
                          │ compiles to BPF
┌─────────────────────────▼───────────────────────────────────────┐
│                     Solana sBPF VM                              │
│              (deployed on solana-test-validator / mainnet)      │
└─────────────────────────────────────────────────────────────────┘
```

**外部边界**：
- 向上：为 AI agent 提供 Zig API 与内嵌知识
- 向下：编译为 Solana sBPF ELF，部署到 Solana 网络
- 横向：通过 CPI 与 System Program / Token Program 交互

---

## 3. 模块架构

### 3.1 模块拓扑

```
sdk/zignocchio.zig (统一入口)
│
├── runtime/        (已完成)
│   ├── types.zig        ── 核心类型：Pubkey, Account, AccountInfo, Ref/RefMut
│   ├── entrypoint.zig   ── 零拷贝输入反序列化 + entrypoint 生成
│   ├── syscalls.zig     ── 自动生成的 syscall 绑定（MurmurHash3）
│   ├── log.zig          ── 日志封装
│   ├── pda.zig          ── PDA 推导（findProgramAddress, createProgramAddress）
│   ├── cpi.zig          ── 跨程序调用（invoke, invokeSigned, return data）
│   └── allocator.zig    ── BumpAllocator（32KB heap）
│
├── guard/          (新建)
│   └── guard.zig        ── 6 个安全检查 helper
│       ├── assert_signer
│       ├── assert_writable
│       ├── assert_owner
│       ├── assert_pda
│       ├── assert_discriminator
│       └── assert_rent_exempt
│
├── schema/         (新建)
│   └── schema.zig       ── AccountSchema comptime 接口
│       ├── LEN
│       ├── DISCRIMINATOR
│       ├── validate()
│       └── from_bytes_unchecked()
│
├── system/         (新建)
│   └── system.zig       ── System Program CPI 封装
│       ├── CreateAccount
│       └── Transfer
│
├── idioms/         (新建)
│   └── idioms.zig       ── 通用惯用 helper
│       ├── close_account
│       ├── read_u64_le / write_u64_le
│       └── read_pubkey
│
└── knowledge/      (新建)
    ├── AGENTS.md        ── agent 指引（版本检查、使用路径、陷阱清单）
    ├── anti_patterns.md ── 常见漏洞 + 修复示例
    └── sdk/README.md    ── 更新后包含新模块的使用文档
```

### 3.2 模块职责表

| 模块 | 职责 | 状态 | 关键约束 |
|------|------|------|----------|
| `types` | Solana 核心类型的内存精确映射、borrow 跟踪、RAII guard | 已完成 | 内存布局必须与 Solana C ABI 一致 |
| `entrypoint` | 零拷贝反序列化输入 buffer，生成 C-callconv entrypoint | 已完成 | 不支持 aggregate return（sBPF 限制） |
| `syscalls` | MurmurHash3 解析的 syscall 函数指针 | 已完成 | 常量哈希由 `tools/gen_syscalls.zig` 自动生成 |
| `log` | 日志、CU 监控封装 | 已完成 | 不分配堆内存 |
| `pda` | PDA 推导与验证 | 已完成 | 输出参数模式（非返回值） |
| `cpi` | 跨程序调用、return data | 已完成 | C-ABI 结构体字段顺序必须精确 |
| `allocator` | Bump allocator（向下增长） | 已完成 | 不支持 free / resize |
| `guard` | 运行期安全检查 helper | 新建 | 每个断言失败时返回明确的 `ProgramError` |
| `schema` | comptime 账户布局接口 | 新建 | 用 Zig `comptime` 计算布局，零运行时开销 |
| `system` | System Program CPI 高级封装 | 新建 | 指令数据格式必须与 Solana 一致 |
| `idioms` | 通用工具函数 + 知识注释 | 新建 | 所有函数必须有 doc comment 说明用途和陷阱 |
| `knowledge` | 结构化知识文档 | 新建 | 所有代码示例必须可被 `zig build test` 验证 |

---

## 4. 数据流

### 4.1 程序执行数据流

```
Solana Runtime
      │
      ▼  [*]u8 input buffer
entrypoint.zig::deserialize()
      │
      ▼  (program_id, []AccountInfo, instruction_data)
processInstruction()
      │
      ├──► guard::assert_*()      ── 运行期安全检查
      │
      ├──► schema::AccountSchema  ── comptime 布局验证 + 反序列化
      │
      ├──► cpi::invoke*()         ── 调用外部程序
      │
      └──► idioms::*()            ── 通用操作（close, read/write）
```

### 4.2 Agent 知识消费数据流

```
Agent 遇到 Solana/Zig 任务
      │
      ├──► 读 AGENTS.md ── 获取"先查 Zignocchio 源码"的指令
      │
      ├──► 读 sdk/*.zig doc comments ── 获取 API 用法和陷阱说明
      │
      ├──► 调用 guard/schema API ── 生成带安全检查的代码
      │
      └──► 读 anti_patterns.md ── 避开已知漏洞
```

---

## 5. 关键接口设计

### 5.1 Guard API（运行期）

```zig
pub const guard = struct {
    pub fn assert_signer(account: AccountInfo) ProgramResult;
    pub fn assert_writable(account: AccountInfo) ProgramResult;
    pub fn assert_owner(account: AccountInfo, expected: *const Pubkey) ProgramResult;
    pub fn assert_pda(account: AccountInfo, seeds: []const []const u8, program_id: *const Pubkey, bump: u8) ProgramResult;
    pub fn assert_discriminator(data: []const u8, expected: u8) ProgramResult;
    pub fn assert_rent_exempt(lamports: u64, data_len: usize) ProgramResult;
};
```

**设计决策**：
- 所有 guard 返回 `ProgramResult`，失败时可直接 `try`
- 不内联复杂错误信息（CU 优化），仅返回标准错误码
- 每个函数上方有 doc comment 解释"为什么需要这个检查"（知识注入）

### 5.2 AccountSchema API（编译期）

```zig
pub fn AccountSchema(comptime T: type) type {
    return struct {
        pub const LEN: usize = comptime calculateLayout(T);
        pub const DISCRIMINATOR: u8 = comptime T.discriminator;

        pub fn validate(account: AccountInfo) ProgramResult;
        pub fn from_bytes_unchecked(data: []u8) *T;
    };
}
```

**设计决策**：
- 利用 Zig `comptime` 在编译期计算账户数据布局
- `T` 必须是 `packed struct` 或 `extern struct`，保证内存布局确定
- `validate()` 运行期检查 `data_len >= LEN` 和 discriminator
- `from_bytes_unchecked()` 仅在 validate 通过后使用

### 5.3 System CPI API

```zig
pub const system = struct {
    pub fn createAccount(
        payer: AccountInfo,
        new_account: AccountInfo,
        owner: *const Pubkey,
        space: u64,
        lamports: u64,
    ) ProgramResult;

    pub fn transfer(
        from: AccountInfo,
        to: AccountInfo,
        amount: u64,
    ) ProgramResult;
};
```

**设计决策**：
- 隐藏 C-ABI 转换细节，直接暴露高级 Zig API
- 内部自动构造 `Instruction` 和 `AccountMeta`
- 使用本地变量拷贝 Program ID，规避 Zig 0.16 BPF 常量地址陷阱

---

## 6. 构建架构

```
Zig 源码 (examples/{name}/lib.zig)
      │
      ├──► zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc
      │    (生成 LLVM bitcode)
      │
      └──► sbpf-linker --cpu v2 --export entrypoint -o zig-out/lib/{example_name}.so
           (LTO 链接为 Solana ELF)
```

**构建约束**：
- BPF target: `bpfel-freestanding`
- Optimizer: `ReleaseSmall`（最小化 ELF 体积）
- sBPF CPU: `v2`（无 32-bit jumps）
- Stack size: 4096 bytes

---

## 7. 安全架构

### 7.1 分层安全模型

| 层级 | 机制 | 示例 |
|------|------|------|
| 编译期 | `comptime` 布局验证 | `AccountSchema.LEN` 编译期计算 |
| 运行期 - 前置 | `guard::*` 断言 | `assert_signer`, `assert_owner` |
| 运行期 - 数据 | borrow 跟踪 | `tryBorrowMutData()` RAII guard |
| 运行期 - 交互 | CPI 前校验 | `invokeSigned` 前检查 writable flag |
| 知识层 | doc comment 陷阱提示 | Zig 0.16 module-scope const 地址问题 |

### 7.2 Borrow 状态机

```
Account.borrow_state (u8 bit-packed)

Bits 7-4: lamports borrow state
  ├─ bit 7: mutable borrow flag (1 = available, 0 = borrowed)
  └─ bits 6-4: immutable borrow count (0-7)

Bits 3-0: data borrow state
  ├─ bit 3: mutable borrow flag (1 = available, 0 = borrowed)
  └─ bits 2-0: immutable borrow count (0-7)

Initial state: 0b_1111_1111
```

---

## 8. 错误处理策略

- 所有可恢复错误统一使用 `ProgramResult`（`error` union + `!void`）
- 错误码映射到 u64，与 Solana 运行时兼容（`errors.errorToU64`）
- Guard 失败返回具体错误类型，便于 agent 理解和调试
- 不 panic，所有异常路径显式返回错误

---

## 9. 依赖关系

**零外部依赖**（Zero dependencies）：
- 不依赖任何第三方 Zig 包（`build.zig.zon` 中无 dependencies）
- 不依赖 Rust crate（除构建时工具 `sbpf-linker`）
- 不依赖 Node.js 运行时（仅测试基础设施使用）

**构建时唯一外部工具**：
- `sbpf-linker`：cargo install 的 LLVM LTO linker

---

## 10. 扩展路径

按优先级：
1. **Guard + Schema + System CPI + Idioms**（Phase 3-6 当前重点）
2. **Token Program CPI**（ATA、Transfer、CloseAccount）
3. **@zignocchio/client npm 包**（TypeScript 类型和 helper）
4. **MCP Server**（agent 通过 MCP 查询知识）
5. **zignocchio-cli**（项目脚手架）

---

## 11. Phase 2 验收标准

- [x] 系统边界清晰（SDK ↔ Agent ↔ Solana VM）
- [x] 模块拓扑和职责已定义
- [x] 关键接口（Guard / Schema / System CPI）已设计
- [x] 构建架构和约束已记录
- [x] 安全分层模型和 borrow 状态机已文档化
- [x] 零依赖策略已确认
- [x] 扩展路径已规划

**可进入 Phase 3: Technical Spec**
