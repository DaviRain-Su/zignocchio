> 状态：Draft
> 日期：2026-04-15
> 版本：v1.0

* * *

## 1. 文档范围

本文档定义 Zignocchio Phase 3-6 新增模块的**技术规格**，包括：

- `sdk/guard.zig` — 安全检查 helper
- `sdk/schema.zig` — `AccountSchema` comptime 接口
- `sdk/system.zig` — System Program CPI 封装
- `sdk/idioms.zig` — 通用惯用 helper
- `AGENTS.md` / `sdk/anti_patterns.md` — 知识文档规格

**前提**：`sdk/types.zig`、`sdk/entrypoint.zig`、`sdk/cpi.zig` 等运行时核心已完成，本文档只描述新增模块。

---

## 2. Solana 安全审计清单（完整版）

按 Pinocchio / Solana 安全审计标准，guard helper 应覆盖以下检查项。第一批实现 6 个，其余作为 backlog。

| # | 检查项 | 对应 Guard | 优先级 | 状态 |
|---|--------|-----------|--------|------|
| 1 | Account 是否为 signer | `assert_signer` | P0 | 第一批 |
| 2 | Account 是否 writable | `assert_writable` | P0 | 第一批 |
| 3 | Account owner 是否正确 | `assert_owner` | P0 | 第一批 |
| 4 | Account 是否为预期 PDA | `assert_pda` | P0 | 第一批 |
| 5 | Account data discriminator 是否匹配 | `assert_discriminator` | P0 | 第一批 |
| 6 | Account 是否 rent exempt | `assert_rent_exempt` | P0 | 第一批 |
| 7 | Account 是否已初始化（非全零） | `assert_initialized` | P1 | backlog |
| 8 | Account 是否未初始化（全零） | `assert_uninitialized` | P1 | backlog |
| 9 | Account data 长度是否 ≥ 预期 | `assert_min_data_len` | P1 | backlog |
| 10 | 两个 Account 是否不是同一地址 | `assert_keys_not_equal` | P1 | backlog |
| 11 | Program ID 是否正确 | `assert_program_id` | P1 | backlog |
| 12 | Account 是否 executable | `assert_executable` | P2 | backlog |
| 13 | Account 是否不可变（is_writable = false） | `assert_immutable` | P2 | backlog |

---

## 3. Guard 模块 (`sdk/guard.zig`)

### 3.1 设计原则

- **纯函数**：不修改 Account 状态，只读检查
- **统一返回 `ProgramResult`**：失败时可直接 `try`
- **零 CU 浪费**：不构造字符串，只返回标准错误码
- **知识注入**：每个函数上方 doc comment 解释"为什么需要这个检查"

### 3.2 接口定义

```zig
const sdk = @import("zignocchio.zig");

pub const guard = struct {
    /// Assert that the account is a signer.
    /// Fails with `MissingRequiredSignature` if not.
    pub fn assert_signer(account: sdk.AccountInfo) sdk.ProgramResult;

    /// Assert that the account is writable.
    /// Fails with `ImmutableAccount` if not.
    pub fn assert_writable(account: sdk.AccountInfo) sdk.ProgramResult;

    /// Assert that the account is owned by the expected program.
    /// Fails with `IncorrectProgramId` if not.
    pub fn assert_owner(account: sdk.AccountInfo, expected: *const sdk.Pubkey) sdk.ProgramResult;

    /// Assert that the account's key matches the PDA derived from seeds + program_id + bump.
    /// Fails with `IncorrectProgramId` if derivation mismatch.
    pub fn assert_pda(
        account: sdk.AccountInfo,
        seeds: []const []const u8,
        program_id: *const sdk.Pubkey,
        bump: u8,
    ) sdk.ProgramResult;

    /// Assert that the account data starts with the expected discriminator byte.
    /// Fails with `InvalidAccountData` if mismatch or data too short.
    pub fn assert_discriminator(data: []const u8, expected: u8) sdk.ProgramResult;

    /// Assert that the account has enough lamports to be rent exempt for the given data_len.
    /// Fails with `AccountNotRentExempt` if not.
    pub fn assert_rent_exempt(lamports: u64, data_len: usize) sdk.ProgramResult;
};
```

### 3.3 实现规格

#### `assert_signer`

```zig
pub fn assert_signer(account: sdk.AccountInfo) sdk.ProgramResult {
    if (!account.isSigner()) {
        return error.MissingRequiredSignature;
    }
}
```

**边界条件**：
- ✅ account.is_signer == 1 → PASS
- ❌ account.is_signer == 0 → `MissingRequiredSignature`

#### `assert_writable`

```zig
pub fn assert_writable(account: sdk.AccountInfo) sdk.ProgramResult {
    if (!account.isWritable()) {
        return error.ImmutableAccount;
    }
}
```

**边界条件**：
- ✅ account.is_writable == 1 → PASS
- ❌ account.is_writable == 0 → `ImmutableAccount`

#### `assert_owner`

```zig
pub fn assert_owner(account: sdk.AccountInfo, expected: *const sdk.Pubkey) sdk.ProgramResult {
    if (!sdk.pubkeyEq(account.owner(), expected)) {
        return error.IncorrectProgramId;
    }
}
```

**边界条件**：
- ✅ owner 完全匹配 → PASS
- ❌ owner 任一 byte 不同 → `IncorrectProgramId`

#### `assert_pda`

```zig
pub fn assert_pda(
    account: sdk.AccountInfo,
    seeds: []const []const u8,
    program_id: *const sdk.Pubkey,
    bump: u8,
) sdk.ProgramResult {
    var expected: sdk.Pubkey = undefined;
    const bump_seed = &[_]u8{bump};
    const seeds_with_bump = // append bump_seed to seeds
    _ = sdk.createProgramAddress(seeds_with_bump, program_id) catch {
        return error.IncorrectProgramId;
    };
    // 实际上 createProgramAddress 返回 Pubkey，需要比较
}
```

**修正版实现**：

```zig
pub fn assert_pda(
    account: sdk.AccountInfo,
    seeds: []const []const u8,
    program_id: *const sdk.Pubkey,
    bump: u8,
) sdk.ProgramResult {
    // 构造带 bump 的 seeds
    var all_seeds: [sdk.MAX_SEEDS + 1][]const u8 = undefined;
    for (seeds, 0..) |seed, i| {
        all_seeds[i] = seed;
    }
    const bump_seed = &[_]u8{bump};
    all_seeds[seeds.len] = bump_seed;

    const expected = sdk.createProgramAddress(all_seeds[0 .. seeds.len + 1], program_id) catch {
        return error.IncorrectProgramId;
    };

    if (!sdk.pubkeyEq(account.key(), &expected)) {
        return error.IncorrectProgramId;
    }
}
```

**边界条件**：
- ✅ key 与 createProgramAddress 结果匹配 → PASS
- ❌ key 不匹配 → `IncorrectProgramId`
- ❌ createProgramAddress 失败（非法 PDA）→ `IncorrectProgramId`
- ❌ seeds.len == MAX_SEEDS 且再加 bump 超出 → `IncorrectProgramId`

#### `assert_discriminator`

```zig
pub fn assert_discriminator(data: []const u8, expected: u8) sdk.ProgramResult {
    if (data.len < 1 or data[0] != expected) {
        return error.InvalidAccountData;
    }
}
```

**边界条件**：
- ✅ data.len >= 1 且 data[0] == expected → PASS
- ❌ data.len == 0 → `InvalidAccountData`
- ❌ data[0] != expected → `InvalidAccountData`

#### `assert_rent_exempt`

```zig
/// Rent exemption: 2 years of rent at 3480 bytes/year base, plus 19.055441 lamports/byte/year.
/// Simplified: rent_exempt = 128 * ((data_len + 127) / 128) for small accounts is NOT exact.
/// We use the Solana formula: rent_exempt = rent_due_for_2_years.
/// For simplicity in BPF, we precompute a lookup for common sizes and fallback to a linear approximation.
pub fn assert_rent_exempt(lamports: u64, data_len: usize) sdk.ProgramResult {
    const required = rentExemptMinimum(data_len);
    if (lamports < required) {
        return error.AccountNotRentExempt;
    }
}
```

**Rent 计算策略**：
- Solana rent exempt 公式：`((account_data_size + 128) / 256) * 2 * 3480`
- 更精确：使用 `rent_epoch = 0` 时所有新账户必须 rent exempt 的共识
- 由于 syscall `sol_get_rent_sysvar` 可用，更精确的做法是读取 sysvar。但在零依赖 SDK 中，我们用**保守估计**：`required = ((data_len + 128) / 256 + 1) * 6960`
- **Phase 3 决定**：使用简化公式 `((data_len / 256) + 1) * 6960`，对于小账户偏保守（要求略高），确保安全性

**边界条件**：
- ✅ lamports >= required → PASS
- ❌ lamports < required → `AccountNotRentExempt`
- ❌ data_len == 0 → required = 6960（保守值）

### 3.4 错误码映射

| Guard | 失败错误码 |
|-------|-----------|
| `assert_signer` | `MissingRequiredSignature` (5) |
| `assert_writable` | `ImmutableAccount` (17) |
| `assert_owner` | `IncorrectProgramId` (11) |
| `assert_pda` | `IncorrectProgramId` (11) |
| `assert_discriminator` | `InvalidAccountData` (2) |
| `assert_rent_exempt` | `AccountNotRentExempt` (12) |

### 3.5 单元测试规格

每个 guard 需要以下测试用例：

| Guard | Happy Path | Boundary | Error/Attack |
|-------|-----------|----------|--------------|
| `assert_signer` | signer=true | - | signer=false |
| `assert_writable` | writable=true | - | writable=false |
| `assert_owner` | owner 匹配 | - | owner 差 1 byte |
| `assert_pda` | seeds+bump 匹配 | MAX_SEEDS | 错 bump、错 seeds |
| `assert_discriminator` | data[0] 匹配 | data.len = 1 | data.len = 0、错 discriminator |
| `assert_rent_exempt` | 刚好满足 | data_len = 0 | 差 1 lamport |

---

## 4. Schema 模块 (`sdk/schema.zig`)

### 4.1 设计原则

- **comptime 优先**：布局在编译期计算，零运行时开销
- **确定性布局**：要求 `T` 必须是 `packed struct` 或 `extern struct`
- **安全优先**：提供 `from_bytes` safe wrapper，降低 agent 误用风险

### 4.2 接口定义

```zig
pub fn AccountSchema(comptime T: type) type {
    return struct {
        pub const LEN: usize = comptime calculateLen(T);
        pub const DISCRIMINATOR: u8 = comptime T.discriminator;

        /// Validate account data length and discriminator.
        pub fn validate(account: sdk.AccountInfo) sdk.ProgramResult;

        /// Deserialize account data into T pointer WITHOUT validation.
        /// Caller MUST call validate() first.
        pub fn from_bytes_unchecked(data: []u8) *T;

        /// Safe wrapper: validate then deserialize.
        pub fn from_bytes(account: sdk.AccountInfo) sdk.ProgramError!*T;
    };
}
```

### 4.3 实现规格

#### `calculateLen`

```zig
fn calculateLen(comptime T: type) usize {
    comptime {
        const info = @typeInfo(T);
        if (info != .Struct) {
            @compileError("AccountSchema requires a struct type");
        }
        if (info.Struct.layout != .packed and info.Struct.layout != .extern) {
            @compileError("AccountSchema requires packed or extern struct layout");
        }
        return @sizeOf(T);
    }
}
```

#### `validate`

```zig
pub fn validate(account: sdk.AccountInfo) sdk.ProgramResult {
    if (account.dataLen() < LEN) {
        return error.AccountDataTooSmall;
    }
    const data = account.borrowDataUnchecked();
    if (data.len < 1 or data[0] != DISCRIMINATOR) {
        return error.InvalidAccountData;
    }
}
```

#### `from_bytes_unchecked`

```zig
pub fn from_bytes_unchecked(data: []u8) *T {
    return @as(*T, @ptrCast(@alignCast(data.ptr)));
}
```

#### `from_bytes` (safe wrapper)

```zig
pub fn from_bytes(account: sdk.AccountInfo) sdk.ProgramError!sdk.RefMut([]u8) {
    try validate(account);
    return account.tryBorrowMutData();
}
```

### 4.4 使用示例

```zig
const MyAccount = extern struct {
    pub const discriminator: u8 = 0xAB;

    discriminator: u8,
    owner: sdk.Pubkey,
    amount: u64,
};

const Schema = sdk.AccountSchema(MyAccount);

try Schema.validate(account);
var account_data = Schema.from_bytes_unchecked(try account.tryBorrowMutData());
account_data.amount = 42;
```

### 4.5 边界条件与测试规格

| 场景 | 输入 | 预期 |
|------|------|------|
| Happy Path | data_len = LEN, discriminator 匹配 | `validate` PASS, `from_bytes` 成功 |
| Boundary | data_len = LEN + N (N > 0) | `validate` PASS |
| Error | data_len = LEN - 1 | `AccountDataTooSmall` |
| Error | data_len = 0 | `AccountDataTooSmall` |
| Error | discriminator 不匹配 | `InvalidAccountData` |
| Compile Error | T 不是 struct | `@compileError` |
| Compile Error | T 是 auto layout struct | `@compileError` |
| Compile Error | T 缺少 `discriminator` 字段/常量 | `@compileError` |

### 4.6 `discriminator` 常量检测

```zig
comptime {
    if (!@hasDecl(T, "DISCRIMINATOR")) {
        @compileError("AccountSchema type must declare a `DISCRIMINATOR` constant");
    }
    if (@TypeOf(T.DISCRIMINATOR) != u8) {
        @compileError("AccountSchema `DISCRIMINATOR` must be of type u8");
    }
}
```

---

## 5. System CPI 模块 (`sdk/system.zig`)

### 5.1 设计原则

- 隐藏 C-ABI 转换和指令数据序列化细节
- 所有 Program ID 使用本地变量拷贝，规避 Zig 0.16 BPF 常量地址陷阱
- 参数顺序遵循 Solana 惯例：payer → new_account → owner/space/lamports

### 5.2 System Program ID

```zig
pub fn getSystemProgramId(out: *sdk.Pubkey) void {
    out.* = .{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
}
```

### 5.3 接口定义

```zig
pub const system = struct {
    /// Create a new account via System Program CPI.
    /// Accounts: payer (signer, writable), new_account (writable)
    pub fn createAccount(
        payer: sdk.AccountInfo,
        new_account: sdk.AccountInfo,
        owner: *const sdk.Pubkey,
        space: u64,
        lamports: u64,
    ) sdk.ProgramResult;

    /// Transfer lamports via System Program CPI.
    /// Accounts: from (signer, writable), to (writable)
    pub fn transfer(
        from: sdk.AccountInfo,
        to: sdk.AccountInfo,
        amount: u64,
    ) sdk.ProgramResult;
};
```

### 5.4 指令数据格式

**CreateAccount** 指令数据：

```
[4 bytes] instruction index = 0 (u32 LE)
[8 bytes] lamports (u64 LE)
[8 bytes] space (u64 LE)
[32 bytes] owner (Pubkey)
```

总计 52 bytes。

**Transfer** 指令数据：

```
[4 bytes] instruction index = 2 (u32 LE)
[8 bytes] amount (u64 LE)
```

总计 12 bytes。

### 5.5 实现规格

#### `createAccount`

```zig
pub fn createAccount(
    payer: sdk.AccountInfo,
    new_account: sdk.AccountInfo,
    owner: *const sdk.Pubkey,
    space: u64,
    lamports: u64,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [52]u8 = undefined;
    @memset(&ix_data, 0);

    // instruction index = 0
    const ix_ptr = @as(*u32, @ptrCast(@alignCast(&ix_data[0])));
    ix_ptr.* = 0;

    // lamports
    const lamports_ptr = @as(*u64, @ptrCast(@alignCast(&ix_data[4])));
    lamports_ptr.* = lamports;

    // space
    const space_ptr = @as(*u64, @ptrCast(@alignCast(&ix_data[12])));
    space_ptr.* = space;

    // owner
    @memcpy(ix_data[20..52], owner[0..32]);

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = payer.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = new_account.key(), .is_signer = false, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ payer, new_account });
}
```

#### `transfer`

```zig
pub fn transfer(
    from: sdk.AccountInfo,
    to: sdk.AccountInfo,
    amount: u64,
) sdk.ProgramResult {
    var system_program_id: sdk.Pubkey = undefined;
    getSystemProgramId(&system_program_id);

    var ix_data: [12]u8 = undefined;

    // instruction index = 2
    const ix_ptr = @as(*u32, @ptrCast(@alignCast(&ix_data[0])));
    ix_ptr.* = 2;

    // amount
    const amount_ptr = @as(*u64, @ptrCast(@alignCast(&ix_data[4])));
    amount_ptr.* = amount;

    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = from.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = to.key(), .is_signer = false, .is_writable = true },
    };

    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };

    try sdk.invoke(&instruction, &[_]sdk.AccountInfo{ from, to });
}
```

### 5.6 边界条件与测试规格

| 函数 | Happy Path | Boundary | Error/Attack |
|------|-----------|----------|--------------|
| `createAccount` | 正常创建 | space = 0, lamports = rent exempt min | payer 不是 signer |
| `transfer` | 正常转账 | amount = 1, amount = u64 max | from 不是 signer, amount = 0 |

**前置检查责任**：
- `createAccount` 不重复做 signer/writable 检查（由调用方用 guard 完成）
- `transfer` 同理
- 但 CPI 内部 `sdk.invoke` 会校验 account meta 与 account info 的一致性

---

## 6. Idioms 模块 (`sdk/idioms.zig`)

### 6.1 设计原则

- 封装高频操作，减少 agent 重复写样板代码
- 每个函数带 doc comment 说明用途、参数、陷阱
- 不引入新的抽象概念，保持显式

### 6.2 接口定义

```zig
pub const idioms = struct {
    /// Close an account by transferring all lamports to the destination
    /// and zeroing out the account data (first byte set to 0).
    /// This does NOT reallocate; it just drains lamports and clears state.
    pub fn close_account(account: sdk.AccountInfo, destination: sdk.AccountInfo) sdk.ProgramResult;

    /// Read a little-endian u64 from account data at the given offset.
    /// Fails with `InvalidAccountData` if offset + 8 > data.len.
    pub fn read_u64_le(data: []const u8, offset: usize) sdk.ProgramError!u64;

    /// Write a little-endian u64 to account data at the given offset.
    /// Fails with `InvalidAccountData` if offset + 8 > data.len.
    pub fn write_u64_le(data: []u8, offset: usize, value: u64) sdk.ProgramResult;

    /// Read a Pubkey (32 bytes) from account data at the given offset.
    /// Fails with `InvalidAccountData` if offset + 32 > data.len.
    pub fn read_pubkey(data: []const u8, offset: usize) sdk.ProgramError!sdk.Pubkey;
};
```

### 6.3 实现规格

#### `close_account`

```zig
pub fn close_account(account: sdk.AccountInfo, destination: sdk.AccountInfo) sdk.ProgramResult {
    // Transfer all lamports
    var dest_lamports = try destination.tryBorrowMutLamports();
    defer dest_lamports.release();

    var src_lamports = try account.tryBorrowMutLamports();
    defer src_lamports.release();

    const amount = src_lamports.value.*;
    src_lamports.value.* = 0;
    dest_lamports.value.* += amount;

    // Zero out first byte as discriminator clear
    var data = account.borrowMutDataUnchecked();
    if (data.len > 0) {
        data[0] = 0;
    }
}
```

**注意**：这里不调用 System Program transfer，而是直接操作 lamports（在 BPF 中，同一 transaction 内的 account lamports 可以直接修改）。这是 Pinocchio 的惯用做法。

#### `read_u64_le`

```zig
pub fn read_u64_le(data: []const u8, offset: usize) sdk.ProgramError!u64 {
    if (offset + 8 > data.len) {
        return error.InvalidAccountData;
    }
    const ptr = @as(*const u64, @ptrCast(@alignCast(data.ptr + offset)));
    return ptr.*;
}
```

**对齐问题**：Solana account data 按 8-byte 对齐（BPF_ALIGN_OF_U128 = 8），u64 读取天然对齐。但为安全起见，如果 offset 可能不对齐，使用 `std.mem.readIntLittle(u64, data[offset..offset+8])` 更安全。

**Phase 3 决定**：使用 `std.mem.readIntLittle(u64, data[offset..offset+8])`，避免对齐假设。

#### `write_u64_le`

```zig
pub fn write_u64_le(data: []u8, offset: usize, value: u64) sdk.ProgramResult {
    if (offset + 8 > data.len) {
        return error.InvalidAccountData;
    }
    const ptr = @as(*u64, @ptrCast(@alignCast(data.ptr + offset)));
    ptr.* = value;
}
```

同上，改用 `std.mem.writeIntLittle(u64, data[offset..offset+8], value)` 更安全。

#### `read_pubkey`

```zig
pub fn read_pubkey(data: []const u8, offset: usize) sdk.ProgramError!sdk.Pubkey {
    if (offset + 32 > data.len) {
        return error.InvalidAccountData;
    }
    var pk: sdk.Pubkey = undefined;
    @memcpy(&pk, data[offset .. offset + 32]);
    return pk;
}
```

### 6.4 边界条件与测试规格

| 函数 | Happy Path | Boundary | Error |
|------|-----------|----------|-------|
| `close_account` | 正常关闭 | account data len = 0 | - |
| `read_u64_le` | offset = 0 | offset = data.len - 8 | offset = data.len - 7 |
| `write_u64_le` | offset = 0 | offset = data.len - 8 | offset = data.len - 7 |
| `read_pubkey` | offset = 0 | offset = data.len - 32 | offset = data.len - 31 |

---

## 7. 知识文档规格

### 7.1 `AGENTS.md`

**目标读者**：AI code agent（Claude Code / Codex / Cursor / Kimi 等）

**必须包含的章节**：

1. **版本检查清单** — 使用前检查 Zig 版本、Solana 版本、sbpf-linker 版本
2. **知识来源声明** — "你的训练数据可能不包含 Zignocchio / Zig BPF，请以本 SDK 的 doc comments 为准"
3. **快速入口** — `const sdk = @import("sdk/zignocchio.zig")`
4. **安全编码清单** — 每个 instruction 开头必须调用的 guard 序列
5. **Zig 0.16 陷阱** — module-scope const 地址问题、inline string data、sBPF 不支持 aggregate return
6. **反模式速查** — 链接到 `sdk/anti_patterns.md`
7. **示例学习路径** — hello → counter → vault → token-vault

### 7.2 `sdk/anti_patterns.md`

**必须覆盖的反模式**：

| # | 反模式 | 后果 | 修复 |
|---|--------|------|------|
| 1 | 直接取 module-scope const 的地址传给 syscall/CPI | `Access violation` | 先拷贝到本地变量 |
| 2 | 忘记检查 signer | 任何人可调用敏感指令 | `guard.assert_signer` |
| 3 | 忘记检查 owner | 伪造账户攻击 | `guard.assert_owner` |
| 4 | 用错 PDA seeds | 资金转入错误地址 | `guard.assert_pda` |
| 5 | 不检查 discriminator 直接反序列化 | 类型混淆 | `Schema.validate` |
| 6 | 双重可变 borrow | `AccountBorrowFailed` | 用 RAII guard + defer release |
| 7 | CPI 前没释放 borrow | CPI 内再 borrow 失败 | CPI 前确保所有 borrow 已 release |
| 8 | 账户没 rent exempt | 创建失败或被 rent 清空 | `guard.assert_rent_exempt` |

### 7.3 `sdk/README.md` 更新

在现有 README 基础上新增：
- Guard 模块使用说明
- AccountSchema 使用说明
- System CPI 使用说明
- Idioms 使用说明
- 所有新增代码示例必须能通过 `zig build test` 验证

---

## 8. 入口文件更新 (`sdk/zignocchio.zig`)

新增 re-export：

```zig
pub const guard = @import("guard.zig");
pub const schema = @import("schema.zig");
pub const system = @import("system.zig");
pub const idioms = @import("idioms.zig");
```

---

## 9. 测试策略

### 9.1 测试分类

按 dev-lifecycle Phase 5 要求，每个模块测试覆盖：

1. **Happy Path** — 正常输入，期望成功
2. **Boundary** — 边界值（最小、最大、刚好满足条件）
3. **Error/Attack** — 异常输入、攻击向量

### 9.2 测试基础设施

- **guard / schema / idioms**：用 Zig `zig build test` 在 host 上运行单元测试
- **system CPI**：通过示例程序（如 vault）的 surfpool 集成测试覆盖
- **所有 doc comment 中的代码示例**：确保能被 `zig test` 解析为 doctest（Zig 原生支持 `/// ```zig` 代码块测试）

### 9.3 各模块测试用例数

| 模块 | Happy Path | Boundary | Error/Attack | 总计 |
|------|-----------|----------|--------------|------|
| guard | 6 | 4 | 6 | 16 |
| schema | 3 | 3 | 4 | 10 |
| system | 2 | 2 | 2 | 6 |
| idioms | 4 | 4 | 4 | 12 |
| **总计** | **15** | **13** | **16** | **44** |

---

## 10. Phase 3 验收标准

- [x] 所有新增模块的接口已定义
- [x] 数据结构、边界条件、错误码已精确描述
- [x] 安全审计完整清单已列出（13 项，第一批 6 项）
- [x] 测试策略和用例数已确认（44 个单元测试）
- [x] 知识文档规格已定义
- [x] 与现有运行时模块的集成点已明确

**可进入 Phase 4: Task Breakdown**
