> 状态：已验证
> 日期：2026-04-15

* * *

## 一句话描述

Zignocchio 是一个**零依赖的 Zig SDK**，让 AI code agent 立刻成为精通 Solana 程序开发的高级工程师——知识捆绑在源码内，版本锁定，显式安全检查与 comptime 约束，不依赖 web search 或过时的训练数据。

---

## 问题定义

**Solana + Zig 开发的完整链路**

```
合约（Zig/Zignocchio） → 客户端 SDK（TypeScript） → 前端 UI
        ↑                        ↑                    ↑
    代码 + 知识              纯知识覆盖           赛后/未覆盖
```

**现状（没有 Zignocchio 的成熟 harness 层）**

AI code agent 用 Zig 写 Solana 程序时：

- **Web search** → 找到过时信息（Anchor 旧版 API、已弃用模式），几乎找不到 Zig 相关内容
- **训练数据** → 不包含 Zignocchio / Zig BPF（太新、太小众）
- **产出代码** → 反模式、缺少安全检查、不符合 Pinocchio 惯用法
- **客户端代码** → 账户反序列化偏移量与合约不匹配（#1 客户端 bug）
- **Zig 0.16 后端陷阱** → agent 不了解模块级常量在 BPF 下的地址异常问题，直接崩溃
- **人类** → 花大量时间审查修复 agent 的每一行输出，agent 的价值被抵消

**期望（有完整的 Zignocchio harness 层）**

- Agent 读捆绑知识 → 遵循惯用法
- 用 `guard::*` → 安全检查机械化
- 用 `AccountSchema` → 账户布局不再混乱
- 客户端知识从同一 SDK 获取 → 两端布局精确匹配
- 代码一次就对 → 人类只需审查业务逻辑

---

## 它是什么 / 不是什么

### 是什么

一个 **Solana Agent Harness for Zig** —— 为 AI coding agents 构建的**知识层 + 约束层 + 运行时层**统一 SDK。

在 Harness Engineering 的框架中（Agent = Model + Harness），Zignocchio 是 harness 的关键部件：不改变 LLM 模型，而是**工程化地改造 agent 的环境**——通过显式 API、comptime 验证、结构化知识注入，让 agent 不可能犯已知的错误。

核心做三件事：

1. **零依赖运行时** — 输入反序列化、borrow 跟踪、syscalls、CPI。 already done。
2. **约束层（Guard + Schema）** — `guard::*` 强制安全检查，`AccountSchema` comptime 接口定义账户布局。不是宏魔法，展开后就是标准 Zig 代码，agent 完全看得懂。
3. **捆绑知识** — 知识以 Zig doc comments 形式内嵌在源码中。`zig build test` 自动验证代码示例，不存在"文档过时但代码更新了"的问题。覆盖：合约侧（账户模型、指令模式、安全检查、惯用法、反模式）+ 客户端侧（交易构建、PDA 推导、账户反序列化）。
4. **AGENTS.md 指引** — 告诉 agent："你的训练数据过时了，读 zignocchio 源码的 doc comments 才是真相来源。"

### 不是什么

- **不是新的 Solana 框架**（不替代 Pinocchio 哲学，而是用 Zig 原生实现它）
- **不是脚手架生成器**（不只做项目模板）
- **不是静态文档站**（不是给人类读的 docs，是给 agent 消费的结构化知识）
- **不是 Anchor 那样的宏魔法**（不隐藏复杂度，让复杂度对 agent 可见可理解）
- **不是 Rust 的 Geppetto 移植**（虽然受 Geppetto 启发，但利用 Zig 的 comptime 做更原生的约束）

---

## 灵感来源

| 来源 | 借鉴了什么 |
| --- | --- |
| **Harness Engineering** | Agent = Model + Harness；工程化改造环境而非优化 prompt；编译期约束比运行期建议更可靠 |
| **Geppetto** (Rust) | 知识层 + 约束层的 agent harness 哲学；guard/schema/dispatch/anti-patterns 模块划分 |
| **Pinocchio** | 零依赖、显式、零拷贝的 Solana 程序开发哲学 |
| **Zig comptime** | 用编译期计算替代宏魔法，agent 可读可理解 |
| dev-lifecycle | 开发阶段约束、技术规格先于代码 |

**Zignocchio 在 Harness Engineering 中的位置：**

```
Prompt Engineering → Context Engineering → Harness Engineering
  "写更好的提示"     "喂更好的上下文"       "工程化改造环境"
                                              ↑
                                        Zignocchio
                              (运行时 + 知识层 + 约束层 harness)
```

---

## 竞品分析

### Geppetto (Rust)

与 Geppetto 共享相同的 Harness Engineering 哲学，但服务于**不同的语言生态**。

| 维度 | Geppetto (Rust) | Zignocchio (Zig) |
| --- | --- | --- |
| 语言 | Rust | Zig |
| 底层框架 | Pinocchio crate | 自研零依赖运行时 |
| 约束机制 | Trait + 类型系统 | `comptime` + 显式函数调用 |
| 宏魔法 | 零宏 | 零宏（Zig 无宏系统） |
| 目标用户 | Rust Solana 开发者 | Zig Solana 开发者 |
| 关系 | **互补** — 同一哲学在不同语言生态的落地 | |

### solana-dev-skill（Solana Foundation）

Claude Code 官方 skill，纯 markdown 文件，Anchor 为默认程序框架。

| 维度 | solana-dev-skill | Zignocchio |
| --- | --- | --- |
| 形态 | 纯 markdown 文件 | Zig 源码（代码 + 知识合一） |
| 知识更新 | 手动更新，锁定在固定版本 | `zig fetch` / git submodule 自动获取 |
| 程序框架 | Anchor 为默认 | Zig-native，Pinocchio-first |
| 强制力 | 零——只是建议 | 有——`guard::*` 是真实 API，调用即检查 |
| 代码验证 | 无 | `zig build test` 自动验证 doc test |
| 关系 | **互补** — skill 教"Solana 是什么"，Zignocchio 教"怎么写对 Zig 代码" | |

### 竞品定位总结

```
            Human DX ←───────────────────────→ Agent DX
               │                                  │
  Anchor ─── Quasar ────────────── Geppetto ─────┘
  (宏,慢)    (宏,快)              (Rust,显式)
               │                       │
               │                  Zignocchio
               │                  (Zig, comptime)
               │                       │
               └── 竞争 ─────────── 互补 ── solana-dev-skill
                  (框架 vs SDK)      (广浅 vs 深专)
```

---

## 目标用户

用 AI code agent（Claude Code、Codex、Cursor 等）+ **Zig** 开发 Solana 程序的开发者。他们希望 agent 产出的代码是：

- 正确的（能编译、能通过 Solana VM）
- 安全的（ signer/owner/PDA 检查不缺漏）
- 符合惯用法的（零拷贝、显式、无隐藏魔法）

---

## 社区验证

核心假设：Solana 开发者社区正在快速采用 AI code agent，但 agent 对 **Zig + Solana** 的支持几乎为零（训练数据不包含）。Zignocchio 填补这个空白。

验证方式：通过完整可运行的示例程序 + 自动化测试套件证明 agent 可以基于 Zignocchio 的文档和 API 直接生成正确代码。

---

## 手动流程（没有 harness 层时开发者怎么做）

1. 打开 Pinocchio Rust 仓库，手动阅读后翻译成 Zig
2. 复制粘贴之前项目的安全检查代码
3. 在 Claude Code 对话中手动粘贴 Zig 文档片段
4. 处理 Zig 0.16 BPF 后端的 `Access violation` 崩溃（原因不明）
5. Agent 产出代码后，逐行对照安全审计清单
6. 手动修复 agent 遗漏的检查

**Zignocchio 将步骤 1-6 自动化**：agent 自动读捆绑知识，自动用 guard helpers，自动避开 Zig 0.16 陷阱，人类只审查业务逻辑。

---

## 关键设计决策

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 语言绑定 | 原生 Zig，不绑定 Rust crate | Zig 的 comptime 和显式哲学比 FFI 更适合 agent-readable 代码 |
| 运行时策略 | 自研零依赖（已存在：entrypoint, types, syscalls, CPI） | 避免任何外部依赖，agent 能追踪每一行代码 |
| Re-export 策略 | `const sdk = @import("sdk/zignocchio.zig")` 统一入口 | 单入口降低 agent 的认知负担 |
| 文档发现机制 | `AGENTS.md` + doc comments + `sdk/README.md` | 知识写在 `.zig` 文件的 doc comments 里，代码和文档合一 |
| Guard helpers 数量 | 第一批 6 个 | 按 Solana 安全审计清单逐条来：signer, writable, owner, pda, discriminator, rent_exempt |
| Schema 机制 | Zig `comptime` 实现的 `AccountSchema` 接口 | 无宏系统，comptime 计算布局对 agent 完全透明 |
| 交付拆分 | SDK 核心和示例程序各走独立 Phase 3-6 | 独立工作流，防止耦合 |
| 知识覆盖策略 | 合约侧：代码 + 知识；客户端侧：纯知识（doc comments） | 不维护两套语言的代码，但知识覆盖全链路 |
| 项目脚手架 | 暂时不做 CLI；示例程序即模板 | 先补齐 harness 层，CLI 赛后优先级提升 |
| 知识保鲜 | 每个知识模块带版本号 + 时间戳 + 适用的 Zig/Solana 版本 | AGENTS.md 指示 agent 使用前检查保鲜期 |
| 测试策略 | surfpool 集成测试（已有）+ 未来 mollusk-svm / litesvm | 保证集成正确性，同时探索 Zig 生态的测试框架 |

---

## 交付范围

### 子模块 A：运行时核心（已完成）

- `sdk/entrypoint.zig` — 零拷贝输入反序列化
- `sdk/types.zig` — Pubkey, Account, AccountInfo, borrow tracking
- `sdk/syscalls.zig` — Solana syscalls
- `sdk/cpi.zig` — Cross-Program Invocation
- `sdk/log.zig` — 程序日志
- `sdk/pda.zig` — PDA 推导
- `sdk/allocator.zig` — BumpAllocator

### 子模块 B：安全约束层（Phase 3-6）

- `sdk/guard.zig` — 第一批 6 个安全检查 helper + 安全知识（doc comments）
  - `assert_signer`
  - `assert_writable`
  - `assert_owner`
  - `assert_pda`
  - `assert_discriminator`
  - `assert_rent_exempt`

### 子模块 C：账户布局约定（Phase 3-6）

- `sdk/schema.zig` — `AccountSchema` comptime 接口 + 账户布局惯用法（doc comments）
  - `LEN`
  - `DISCRIMINATOR`
  - `validate()`
  - `from_bytes_unchecked()`

### 子模块 D：System Program CPI（Phase 3-6）

- `sdk/system.zig` / `sdk/system/` — System Program 的 CPI 封装
  - `CreateAccount`
  - `Transfer`
  - 可能扩展：Assign, Allocate

### 子模块 E：惯用 Helper（Phase 3-6）

- `sdk/idioms.zig` / `sdk/idioms/` — 通用 helper 函数 + 知识
  - `close_account`
  - `read_u64_le` / `write_u64_le`
  - `read_pubkey`

### 子模块 F：知识文档（Phase 3-6）

- `sdk/anti_patterns.md` — 常见漏洞 + 修复（给 agent 看）
- `AGENTS.md` — agent 指引（已存在，需要增强）
- `sdk/README.md` — 更新以包含新模块

### 子模块 G：完整示例程序（Phase 3-6）

- 扩展现有 `vault` / `token-vault` 示例，或新增一个更复杂的示例（如 escrow），展示 guard + schema + system CPI 的完整用法。

### 子模块 H：测试基础设施（持续）

- 全部示例程序的 surfpool 集成测试（已迁移完成）
- 新增 guard / schema / system 的单元测试

---

## 后续演进

按优先级排序：

1. **CLI 脚手架** — `zignocchio-cli new my-program` 生成最小程序骨架
2. **更多 CPI 模块** — ATA、Memo、Token-2022
3. **@zignocchio/client npm 包** — 将客户端知识迁移为 TypeScript 代码和类型定义
4. **MCP server** — agent 通过 MCP 查询知识
5. **自动进化** — CI 追踪 Pinocchio / Zig 上游变更，自动生成知识更新 PR

---

## Phase 1 验收标准

- [x] 问题定义清晰
- [x] 目标用户明确
- [x] "是什么/不是什么"边界定义完成
- [x] 手动流程已描述
- [x] 关键设计决策已记录
- [x] 交付范围已确认
- [x] 竞品定位清晰

**可进入 Phase 2: Architecture**
