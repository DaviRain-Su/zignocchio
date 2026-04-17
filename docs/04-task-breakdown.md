> 状态：Draft
> 日期：2026-04-15
> 版本：v1.0

* * *

## 1. 文档范围

本文档定义 Zignocchio Phase 4-6 的**任务拆分**，基于 `docs/03-technical-spec.md` 将新增模块拆分为可并行执行的子任务，明确每个子任务的交付物、依赖关系、验收标准和负责人。

---

## 2. 拆分原则

- **模块独立优先**：A-D 四个代码模块彼此无依赖，可并行开发
- **测试与代码同任务**：每个子任务包含单元测试/集成测试，不单独拆测试任务
- **文档收口集中**：知识文档（E）和入口文件（F）在代码模块完成后串行收尾
- **单人负责，多人 review**：每个子任务由一人主责，完成后由 @ser9-CC-SONNET review

---

## 3. 子任务清单

### 子任务 A：Guard 模块 (`sdk/guard.zig`)

**交付物**：
- `sdk/guard.zig` — 6 个 guard helper 实现
- `sdk/guard.zig` 内嵌单元测试（16 个用例）

**实现要点**：
- `assert_signer`、`assert_writable`、`assert_owner`、`assert_pda`、`assert_discriminator`、`assert_rent_exempt`
- `assert_pda` 需加 `seeds.len <= MAX_SEEDS` 断言（@ser9-CC-SONNET review 反馈）
- 每个函数带 doc comment 说明检查原因和失败错误码

**验收标准**：
- [ ] `zig build test` 通过 guard 模块全部 16 个测试
- [ ] 错误码映射与 Phase 3 规格一致
- [ ] 所有函数有 doc comment

**依赖**：无
**建议负责人**：@ser9-kimi

---

### 子任务 B：Schema 模块 (`sdk/schema.zig`)

**交付物**：
- `sdk/schema.zig` — `AccountSchema` comptime 接口实现
- `sdk/schema.zig` 内嵌单元测试（10 个用例）

**实现要点**：
- `calculateLen`、`validate`、`from_bytes_unchecked`、`from_bytes`
- `from_bytes` 使用 `tryBorrowMutData()` + `release()`，不绕过 borrow 跟踪（@ser9-CC-SONNET review 反馈）
- `T` 必须是 `packed struct` 或 `extern struct`，否则 `@compileError`
- comptime 检测 `T.discriminator` 存在且类型为 `u8`

**验收标准**：
- [ ] `zig build test` 通过 schema 模块全部 10 个测试
- [ ] comptime 错误在传入非法 `T` 时正确触发
- [ ] `from_bytes` safe wrapper 工作正常

**依赖**：无
**建议负责人**：@ser9-kimi

---

### 子任务 C：System CPI 模块 (`sdk/system.zig`)

**交付物**：
- `sdk/system.zig` — System Program CPI 封装
- 通过示例程序（如 vault）的 surfpool 集成测试覆盖，或内嵌单元测试（6 个用例）

**实现要点**：
- `getSystemProgramId`、`createAccount`、`transfer`
- 指令数据序列化考虑 `std.mem.writeIntLittle` 安全性（@ser9-cc review 反馈）
- 所有 Program ID 使用本地变量拷贝，规避 Zig 0.16 BPF 常量地址陷阱
- 不重复做 signer/writable 检查（由调用方用 guard 完成）

**验收标准**：
- [ ] `zig build` 能成功编译 system 模块
- [ ] 示例程序的 surfpool 集成测试通过（或单元测试 6 个通过）
- [ ] `createAccount` 和 `transfer` 的指令数据格式与 Solana 规格一致

**依赖**：无（但集成测试可能需要现有示例程序）
**建议负责人**：@ser9-kimi

---

### 子任务 D：Idioms 模块 (`sdk/idioms.zig`)

**交付物**：
- `sdk/idioms.zig` — 通用惯用 helper 实现
- `sdk/idioms.zig` 内嵌单元测试（12 个用例）

**实现要点**：
- `close_account`、`read_u64_le`、`write_u64_le`、`read_pubkey`
- `close_account` doc comment 显式说明"直接改 lamports 是同一 transaction 内的 Pinocchio 惯用法，跨 transaction 必须用 `system.transfer`"（@ser9-CC-SONNET review 反馈）
- `read_u64_le` / `write_u64_le` 使用 `std.mem.readIntLittle` / `std.mem.writeIntLittle`，避免对齐假设

**验收标准**：
- [ ] `zig build test` 通过 idioms 模块全部 12 个测试
- [ ] 所有函数有 doc comment
- [ ] `close_account` 的 lamports 操作和 data zeroing 行为正确

**依赖**：无
**建议负责人**：@ser9-kimi

---

### 子任务 E：知识文档更新

**交付物**：
- `AGENTS.md` — agent 指引（版本检查、知识来源、安全编码清单、Zig 0.16 陷阱、反模式速查、示例学习路径）
- `sdk/anti_patterns.md` — 8 个反模式表格
- `sdk/README.md` — 新增 Guard / Schema / System / Idioms 使用说明

**实现要点**：
- 所有代码示例必须能被 `zig build test` 验证
- `AGENTS.md` 明确告知 agent"以本 SDK 的 doc comments 为准"
- `anti_patterns.md` 覆盖 module-scope const 地址陷阱、 signer/owner/PDA 遗漏、discriminator 不检查、双重 mutable borrow、CPI 前未释放 borrow、rent exempt 遗漏

**验收标准**：
- [ ] 三个文档文件内容完整
- [ ] 文档中所有 Zig 代码示例通过 `zig test` 或 `zig build test`
- [ ] @ser9-CC-SONNET review 通过

**依赖**：A-D 完成后进行（需要最终 API 签名稳定）
**建议负责人**：@ser9-kimi

---

### 子任务 F：入口文件与全量构建验证

**交付物**：
- `sdk/zignocchio.zig` — 新增 re-export（guard、schema、system、idioms）
- 全量 `zig build test` 通过
- 全量示例程序 surfpool 集成测试通过

**实现要点**：
- 在 `sdk/zignocchio.zig` 中添加：
  ```zig
  pub const guard = @import("guard.zig");
  pub const schema = @import("schema.zig");
  pub const system = @import("system.zig");
  pub const idioms = @import("idioms.zig");
  ```
- 确保新增 import 不破坏现有运行时模块的编译
- 运行 `zig build test` 和 surfpool 集成测试，修复任何回归

**验收标准**：
- [ ] `sdk/zignocchio.zig` 正确 re-export 四个新模块
- [ ] `zig build test` 全量通过
- [ ] 现有示例程序（vault / token-vault）surfpool 测试无回归
- [ ] 新增示例程序（如 escrow）能正常编译运行（可选，G 子任务）

**依赖**：A-D 完成后进行
**建议负责人**：@ser9-kimi

---

## 4. 依赖关系图

```
A (guard) ──┐
B (schema) ──┼──► E (docs) ──► F (entry + full build)
C (system) ──┤
D (idioms) ──┘
```

**并行路径**：A、B、C、D 可完全并行
**串行路径**：E 和 F 必须在 A-D 完成后执行

---

## 5. 执行建议

### 5.1 并行阶段（Week 1）

由 @ser9-kimi 主导，按以下顺序推进 A-D：

1. 先启动 **A (guard)** 或 **B (schema)** — 这两个模块最独立，测试也最容易在 host 上跑通
2. 同时启动 **D (idioms)** — 逻辑简单，可作为快速胜利
3. **C (system)** 可稍晚启动，因为集成测试依赖 surfpool，需要更多环境准备

### 5.2 Review 节奏

- 每完成一个子任务，@ser9-kimi 在 thread 中 @ser9-CC-SONNET 和 @ser9-cc
- @ser9-CC-SONNET 负责代码/文档 review
- @ser9-cc 负责检查是否符合 Phase 3 技术规格和任务拆分意图

### 5.3 串行收口阶段（Week 1-2）

- A-D 全部完成后，@ser9-kimi 编写 E（知识文档）
- E 通过 review 后，进行 F（入口文件 + 全量构建验证）
- F 通过后，项目进入 **Phase 5: Test Spec**（已有 44 个测试用例覆盖）和 **Phase 6: Implementation 收尾**

---

## 6. 可选子任务 G：完整示例程序

**交付物**：
- 新增一个完整示例程序（如 `examples/escrow/`），展示 guard + schema + system CPI + idioms 的联合用法
- 示例程序附带 surfpool 集成测试

**验收标准**：
- [ ] 示例程序能编译为 sBPF ELF
- [ ] surfpool 集成测试通过
- [ ] 代码作为 agent 学习模板，被 `AGENTS.md` 引用

**依赖**：A-F 全部完成
**优先级**：P1（不阻塞 Phase 4 核心交付，但强烈建议做）
**建议负责人**：@ser9-kimi

---

## 7. 风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| `assert_rent_exempt` 简化公式与 Solana 实际 rent 不一致 | 正常用例被错误拒绝 | 实现后用已知 rent exempt 账户交叉验证（@ser9-cc 反馈） |
| `system.zig` 指令数据序列化对齐问题 | BPF 运行时崩溃 | 优先用 `std.mem.writeIntLittle`，并在 surfpool 中验证（@ser9-cc 反馈） |
| `assert_pda` seeds 拼接越界 | 栈溢出/UB | 实现时加 `seeds.len <= MAX_SEEDS` 断言（@ser9-CC-SONNET 反馈） |
| `from_bytes` 双重 mutable borrow | `AccountBorrowFailed` | 改用 `tryBorrowMutData()` + `release()`（@ser9-CC-SONNET 反馈） |
| surfpool 集成测试环境不稳定 | C 和 F 阻塞 | 先用单元测试覆盖核心逻辑，surfpool 问题单独排查 |

---

## 8. Phase 4 验收标准

- [x] 子任务 A-F 已拆分，交付物和验收标准明确
- [x] 依赖关系清晰，并行/串行路径已标注
- [x] 每个子任务建议负责人已指定
- [x] 风险清单和应对措施已记录
- [x] 可选子任务 G 已规划

**可进入 Phase 5: Test Spec & Phase 6: Implementation**
