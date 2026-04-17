> 状态：Draft
> 日期：2026-04-15
> 版本：v1.0

* * *

## 1. 文档范围

本文档定义 Zignocchio 在 Phase 4-6 核心交付完成后的**下一阶段演进规划**，基于 `docs/01-prd.md` 的后续演进路径和 `docs/04-task-breakdown.md` 中未完成的子任务 G。

---

## 2. 当前状态

Phase 4-6 核心交付（A-F）全部完成并归档：
- A (guard.zig) ✅
- B (schema.zig) ✅
- C (system.zig) ✅
- D (idioms.zig) ✅
- E (AGENTS.md / anti_patterns.md / README.md) ✅
- F (全量构建 + 测试验证) ✅

---

## 3. 下一阶段优先级

### Phase 7: 示例程序 + 扩展模块

#### 3.1 子任务 G：escrow 示例程序（P1）

**目标**：实现一个完整的 escrow 示例程序，展示 guard + schema + system CPI + idioms 的联合用法，验证 A-F 在真实场景下的协同工作能力。

**拆分**：
- **G1**: escrow 合约实现（Zig）
  - 账户结构：EscrowState（使用 `AccountSchema`）
  - 指令路由：Make / Accept / Refund
  - 使用 `guard.assert_signer`、`guard.assert_pda`、`guard.assert_discriminator`
  - 使用 `system.createAccount` 创建 escrow 账户
  - 使用 `idioms.close_account` 关闭 escrow 账户
- **G2**: surfpool 集成测试（TypeScript）
  - Happy path：Maker 创建 escrow → Taker 接受 → 资金释放
  - Refund path：Maker 创建 escrow → Maker 退款 → escrow 关闭
  - 顺便验证 `sdk/system.zig` 在真实 sBPF 环境下的行为
- **G3**: 文档更新
  - README.md / AGENTS.md 将 escrow 加入学习路径（vault 之后）

**依赖**：A-F 全部完成 ✅
**建议负责人**：@ser9-kimi（G1 + G2），@ser9-CC-SONNET review

---

#### 3.2 扩展 Guard 清单（P1）

**目标**：实现安全审计清单中 backlog 的 7 个检查项。

| # | 检查项 | 对应 Guard |
|---|--------|-----------|
| 7 | Account 是否已初始化（非全零） | `assert_initialized` |
| 8 | Account 是否未初始化（全零） | `assert_uninitialized` |
| 9 | Account data 长度是否 ≥ 预期 | `assert_min_data_len` |
| 10 | 两个 Account 是否不是同一地址 | `assert_keys_not_equal` |
| 11 | Program ID 是否正确 | `assert_program_id` |
| 12 | Account 是否 executable | `assert_executable` |
| 13 | Account 是否不可变（is_writable = false） | `assert_immutable` |

**验收标准**：
- 每个 guard 有 doc comment、边界条件说明、单元测试
- `zig build test` 通过
- 错误码映射到标准 `ProgramError`

**依赖**：无（可和 G 并行，但建议 G 完成后做，避免 escrow 返工）
**建议负责人**：@ser9-kimi

---

#### 3.3 Token Program CPI 模块（P2）

**目标**：扩展 `sdk/token/` 下的高频 Token Program 操作封装。

**范围**：
- `sdk/token/ata.zig` — Associated Token Account 创建/关闭
- `sdk/token/transfer.zig` — Token Transfer CPI
- `sdk/token/close_account.zig` — CloseAccount CPI

**验收标准**：
- 每个封装隐藏 C-ABI 转换细节
- 使用本地变量拷贝 Program ID，规避 Zig 0.16 BPF 常量地址陷阱
- 有 surfpool 集成测试或单元测试覆盖

**依赖**：扩展 Guard 清单完成后（部分 Token 操作需要 `assert_initialized`）
**建议负责人**：@ser9-kimi

---

### Phase 8: 开发者体验

#### 3.4 CLI 脚手架（P2）

**目标**：`zignocchio-cli new my-program` 生成最小程序骨架。

**交付物**：
- `zignocchio-cli` 可执行程序（Zig 实现）
- 模板包含：entrypoint、一个示例 instruction、build.zig 配置、surfpool 测试骨架

**依赖**：G + 扩展 Guard 完成后（模板需要展示完整最佳实践）
**建议负责人**：@ser9-kimi

---

#### 3.5 @zignocchio/client npm 包（P3）

**目标**：将客户端知识迁移为 TypeScript 代码和类型定义。

**范围**：
- PDA 推导函数（与合约端一致）
- 账户布局类型定义（与 `AccountSchema` 对齐）
- 交易构建 helper

**依赖**：SDK API 稳定后
**建议负责人**：待定

---

## 4. 执行建议

### 第一阶段（立即启动）
- **G1 + G2**：escrow 合约 + surfpool 测试
- **G3**：文档更新

### 第二阶段（G 完成后启动）
- **扩展 Guard 清单**：7 个 backlog guard

### 第三阶段（Guard 完成后启动）
- **Token Program CPI**

### 第四阶段（SDK 稳定后）
- **CLI 脚手架**
- **@zignocchio/client npm 包**

---

## 5. 验收标准

- [ ] escrow 示例程序编译通过，surfpool 测试通过
- [ ] 7 个 backlog guard 实现并测试通过
- [ ] Token Program CPI 模块实现并测试通过
- [ ] CLI 脚手架可用
- [ ] client npm 包发布（可选）

**可进入 escrow 示例程序实现阶段**
