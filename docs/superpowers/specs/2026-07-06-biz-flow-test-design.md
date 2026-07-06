# 业务流程测试技能 — 设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## 
1. 概述

### 1.1 目标

构建一个可跨 Java 项目复用的 Claude Code 技能（`/biz-test`），通过 Markdown + Gherkin 风格场景文件描述 REST API 调用链路，按顺序执行、逐步骤断言验证，最终沉淀为可重复运行的业务场景测试用例。

### 1.2 非目标

- 不支持 Spring Service/本地 Bean 调用（仅 REST API）
- 不支持并行步骤执行（严格顺序执行）
- 不支持复杂的流程控制（条件分支、循环等）

---

## 2. 文件结构

```
project-root/
├── .claude/skills/
│   └── biz-flow-test.md              # 技能定义（slash command + 执行逻辑）
├── api-env.yml                        # 环境配置
└── test-scenarios/                    # 业务场景目录
    ├── order-create-flow.md
    ├── aml-suspicious-report.md       # 示例：反洗钱可疑交易报送
    └── ...
```

### 2.1 `api-env.yml` — 环境配置

```yaml
base_url: https://aml-test.example.com

auth:
  type: bearer                          # bearer | cookie | basic | none
  token: ${AML_TOKEN}                   # 支持环境变量注入
  refresh:
    enabled: true
    method: POST
    path: /api/auth/refresh
    token_field: $.data.token

http:
  timeout: 30000                        # 单次请求超时（ms）
  retry:
    max: 0                              # 默认不重试

permission:
  prompt_template: |
    步骤 {step} 返回 {status_code}（{reason}）。
    请提供有效的认证信息，或输入以下选项：
    [1] 输入新的 Token/Cookie
    [2] 跳过此步骤
    [3] 终止执行
```

### 2.2 场景文件格式（Markdown + Gherkin）

```markdown
# 场景：<名称>

## 背景
<业务背景描述，可选>

## 前置条件
- <条件1>
- <条件2>

## 公共请求头
Authorization: Bearer {{步骤N.token}}
Content-Type: application/json
<其他场景级公共头>

## 步骤 N：<步骤描述>
- **方法**: POST | GET | PUT | DELETE
- **路径**: /api/xxx/yyy
- **请求头**:                           # 可选，覆盖公共请求头
  X-Custom-Header: value
- **请求体**:                           # 可选
  ```json
  {"key": "value"}
  ```
- **预期**:
  - 状态码: 200
  - `$.field` 为 `"精确值"`
  - 自然语言辅助验证描述
```

**变量引用语法**：`{{步骤N.字段路径}}` 或 `{{env.ENV_VAR}}`。

**断言类型**：
- **精确断言**：JSONPath 路径 + 期望值，严格比对
- **容许多值断言**：`$.field` 属于 `["VAL1", "VAL2", "VAL3"]`
- **自然语言断言**：AI 判断响应是否匹配描述

---

## 3. 执行流程

### 3.1 完整流程

```
1. 加载 api-env.yml → 读取环境级配置
2. 加载 test-scenarios/<name>.md → 解析步骤
3. 按顺序执行每个步骤：
   ├─ 构造请求（URL = base_url + 路径，注入变量，附加请求头）
   ├─ 发起 HTTP 调用（curl）
   ├─ 验证断言 → 精确断言严格比对，自然语言断言 AI 判断
   ├─ 通过 → 继续下一步
   └─ 失败 → 输出期望/实际差异，终止
4. 权限异常拦截：
   ├─ 401 → 尝试 Token 刷新接口
   ├─ 刷新成功 → 更新 Token，重试当前步骤
   └─ 刷新失败 / 403 → 暂停，展示错误和建议，询问用户操作
5. 全部通过 → 固化规则：
   ├─ AI 发现的隐式依赖 → 写入精确 JSONPath 提取规则
   └─ 自然语言断言 → 补充精确断言
6. 输出测试报告
```

### 3.2 固化机制

首次探索执行通过后，技能自动更新场景文件：

- AI 推断的变量依赖（如"步骤2用了上一个返回里的 orderId"）→ 补写为显式的 `提取: $.data.orderId → orderId`
- 纯自然语言的预期描述 → 补充 JSONPath 精确断言
- 后续执行不再依赖 AI 推断，直接使用固化的提取规则

---

## 4. 权限异常处理

| 场景 | 行为 |
|------|------|
| 步骤返回 401 | 若 `api-env.yml` 配置了 `auth.refresh`，自动调用刷新接口；成功则更新 Token 重试，失败则询问用户 |
| 步骤返回 403 | 立即暂停，展示"可能原因：Token 过期、权限不足、IP 白名单限制..."，询问用户操作 |
| 其他 4xx/5xx | 终止流程，输出失败步骤详情 |

---

## 5. 测试报告

```
═══════════════════════════════════════════
  业务流程测试报告
  场景：反洗钱可疑交易报送——完整链路
  环境：https://aml-test.example.com
  时间：2026-07-06 20:15:32
  结果：✅ 全部通过 (8/8)
═══════════════════════════════════════════

  ✅ 步骤1 登录获取Token          200  (0.8s)
  ✅ 步骤2 查询待审核案例列表      200  (1.2s) — 找到 CASE-20260706-001
  ...

  总耗时: 10.2s

  📝 本次固化：
    - 步骤2 补充提取规则 → `$.data.list[?(@.caseNo==...)].id`
    - 步骤7 补充容许值断言 → feedbackStatus ∈ [ACCEPTED,RECEIVED,PENDING]

═══════════════════════════════════════════
```

---

## 6. 边界条件 & 错误处理

| 情况 | 处理 |
|------|------|
| 场景文件不存在 | 列出 `test-scenarios/` 下可用场景 |
| `api-env.yml` 不存在 | 提示用户先创建环境配置文件 |
| 变量引用解析失败 | 提示具体步骤和未解析的变量名 |
| 网络超时 | 根据 `http.timeout` 配置超时，不重试（默认 `retry.max: 0`） |
| JSONPath 提取路径无匹配 | 终止，展示实际返回的 JSON 结构供排查 |
| curl 不可用 | 提示安装 curl 或配置 HTTP 工具路径 |

---

## 7. 跨项目复用

1. 复制 `.claude/skills/biz-flow-test.md` 到目标项目
2. 创建目标项目的 `api-env.yml`（环境地址、认证）
3. 编写 `test-scenarios/*.md` 场景文件
4. 运行 `/biz-test <场景名>`

场景文件与项目绑定（含有该项目的接口），技能和 `api-env.yml` 结构通用。

---

## 8. 技术决策记录

| 决策 | 选择 | 原因 |
|------|------|------|
| 实现形式 | 纯 Claude Code 技能 | 零 Java 依赖，跨项目直接复制 |
| 配置格式 | Markdown + Gherkin | 业务人员可读，版本管理友好 |
| 环境与场景分离 | `api-env.yml` + `test-scenarios/` | 切换环境不改场景文件 |
| 变量依赖发现 | 首次 AI 推断 → 通过后固化为显式规则 | 探索灵活 + 回归稳定 |
| 断言方式 | 精确 JSONPath + 自然语言辅助 | 关键字段不可含糊，其余 AI 辅助 |
| 失败策略 | 任何步骤失败即停止 | 简单可靠，避免级联错误 |