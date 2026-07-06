# 业务流程测试技能 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 `/biz-test` Claude Code 技能，通过 Markdown 场景文件描述 REST API 调用链路，顺序执行并断言验证，沉淀为可重复运行的业务场景测试用例。

**Architecture:** 纯 Claude Code 技能实现，无 Java 代码依赖。技能文件 `.claude/skills/biz-flow-test.md` 定义 slash command 和完整执行逻辑。`api-env.yml` 管理环境配置（base_url、认证）。`test-scenarios/*.md` 用 Markdown + Gherkin 风格描述 API 调用步骤和断言。

**Tech Stack:** Claude Code Custom Slash Command, curl, jq (JSONPath), Markdown, YAML

## Global Constraints

- 仅支持 REST API 调用（curl），不支持 Java 本地方法调用
- 步骤严格顺序执行，不支持并行/条件分支/循环
- 任何步骤断言失败即终止，不重试（默认 retry.max: 0）
- 跨项目复用方式：复制 `.claude/skills/biz-flow-test.md` 到目标项目
- 目标项目需安装 `curl` 和 `jq`

---

## File Structure

```
project-root/
├── .claude/skills/
│   └── biz-flow-test.md              # [CREATE] 技能定义 — slash command + 执行指令
├── api-env.yml                        # [CREATE] 环境配置模板 — base_url、认证、超时
└── test-scenarios/
    └── aml-suspicious-report.md       # [CREATE] 示例场景 — 反洗钱可疑交易报送
```

| 文件 | 职责 | 内容性质 |
|------|------|----------|
| `.claude/skills/biz-flow-test.md` | 技能入口，定义执行流程、curl 调用、断言校验、权限处理、固化逻辑、报告输出 | Claude Code skill 指令（Markdown frontmatter + 执行指令文本） |
| `api-env.yml` | 环境级配置：base_url、认证方式、Token 刷新策略、超时、权限提示模板 | YAML 配置文件 |
| `test-scenarios/aml-suspicious-report.md` | 一个完整的银行反洗钱可疑交易报送业务场景 | Markdown 场景文件 |

### 接口边界

- **`biz-flow-test.md` → `api-env.yml`**：通过 Read 工具读取，消费 `base_url`、`auth.*`、`http.*`、`permission.*` 字段
- **`biz-flow-test.md` → `test-scenarios/*.md`**：通过 Read 工具读取，按正则/标记解析步骤；通过 Edit 工具回写固化规则
- **`biz-flow-test.md` → curl/jq**：通过 Bash 工具执行 curl 发起 HTTP 请求，jq 做 JSONPath 提取和断言

---

### Task 1: 创建环境配置文件 `api-env.yml`

**Files:**
- Create: `api-env.yml`

**Interfaces:**
- Produces: `api-env.yml` 文件，包含 `base_url`、`auth`（含 `type`、`token`、`refresh`）、`http`（含 `timeout`、`retry`）、`permission`（含 `prompt_template`）字段。技能通过 Read 工具读取，按 YAML 解析使用。

- [ ] **Step 1: 创建 `api-env.yml`**

```yaml
# ============================================================
# 业务流程测试 — 环境配置文件
# 说明：存放目标 API 环境的连接信息和认证策略。
#      场景文件只需写相对路径和断言，环境切换改这个文件即可。
# ============================================================

# ---- 目标服务地址 ----
base_url: https://aml-test.example.com

# ---- 认证策略 ----
auth:
  # 认证类型: bearer | cookie | basic | none
  type: bearer

  # Bearer Token（支持 ${ENV_VAR} 环境变量注入）
  token: ${AML_TOKEN}

  # Token 刷新策略（401 时自动尝试）
  refresh:
    enabled: true
    method: POST
    path: /api/auth/refresh
    # 刷新接口请求需要携带的额外字段（如 refreshToken），可选
    body: |
      {"refreshToken": "{{refreshToken}}"}
    # 从刷新接口响应中提取新 Token 的 JSONPath
    token_field: $.data.token

# ---- HTTP 请求配置 ----
http:
  # 单次请求超时（毫秒）
  timeout: 30000
  # 失败重试
  retry:
    max: 0               # 0 = 不重试
    interval: 1000       # 重试间隔（ms）

# ---- 权限异常交互模板 ----
permission:
  prompt_template: |
    步骤 "{step_desc}" 返回了 {status_code}（{reason}）。
    可能原因：Token 过期、权限不足、IP 白名单限制、账号被锁定...
    请输入你的操作：
    [1] 输入新的认证信息（Token/Cookie/账号密码）
    [2] 跳过此步骤，标记为未执行
    [3] 终止整个流程
```

- [ ] **Step 2: 验证 YAML 语法**

```bash
ruby -ryaml -e "YAML.load_file('api-env.yml'); puts 'YAML syntax OK'"
```

期望输出: `YAML syntax OK`

- [ ] **Step 3: 提交**

```bash
git add api-env.yml
git commit -m "feat: add api-env.yml environment config template

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 创建示例场景文件 `test-scenarios/aml-suspicious-report.md`

**Files:**
- Create: `test-scenarios/aml-suspicious-report.md`

**Interfaces:**
- Produces: Markdown 场景文件。技能通过 Read 工具读取，解析 `## 步骤 N` 区块获取步骤定义。每个步骤包含方法、路径、请求头、请求体、预期断言。变量引用为 `{{步骤N.字段路径}}` 或 `{{env.VAR}}`。固化时通过 Edit 工具追加 `**提取:**` 行。

- [ ] **Step 1: 创建目录并编写场景文件**

```bash
mkdir -p test-scenarios
```

然后创建文件 `test-scenarios/aml-suspicious-report.md`：

```markdown
# 场景：反洗钱可疑交易报送——完整链路

## 背景
监管要求银行在发现可疑交易后 5 个工作日内向反洗钱监测分析中心报送。
本场景覆盖从登录、案例审核、报文生成、报送提交到案例归档的完整链路。

## 前置条件
- 操作员需具备角色：AML_OPERATOR（案例审核）+ AML_REPORTER（报文报送）
- 系统需存在预处理完成的可疑案例（案例编号：CASE-20260706-001）
- 案例关联交易金额总和需 > 5万元（大额标准）

## 公共请求头
Authorization: Bearer {{步骤1.token}}
Content-Type: application/json

---

## 步骤 1：登录获取操作员 Token
- **方法**: POST
- **路径**: /api/auth/login
- **请求体**:
  ```json
  {"username": "aml_operator", "password": "{{env.AML_PWD}}"}
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - 返回 Token 和角色列表
  - 角色需包含 `AML_OPERATOR`

---

## 步骤 2：查询待审核可疑案例列表
- **方法**: GET
- **路径**: /api/aml/case/pending?page=1&size=20
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - 返回列表不为空，`$.data.total` > 0
  - 列表中存在案例 `CASE-20260706-001`

---

## 步骤 3：获取案例详情（含关联交易明细）
- **方法**: GET
- **路径**: /api/aml/case/detail?caseId=CASE-20260706-001
- **预期**:
  - 状态码: 200
  - `$.data.caseStatus` 为 `"PENDING_REVIEW"`
  - `$.data.transactions` 数组长度 > 0
  - 每笔交易的 `amount`、`counterParty`、`txTime` 字段齐全
  - 涉及金额总和 > 5万元

---

## 步骤 4：审核案例——标记为"需上报"
- **方法**: PUT
- **路径**: /api/aml/case/review
- **请求体**:
  ```json
  {
    "caseId": "CASE-20260706-001",
    "reviewResult": "REPORTABLE",
    "riskLevel": "HIGH",
    "reviewComment": "交易模式与洗钱特征高度吻合：短期内多笔大额分散转入、集中转出，对手方涉及高风险地区"
  }
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - `$.data.caseStatus` 更新为 `"APPROVED_FOR_REPORTING"`
  - 审核记录生成，`$.data.reviewId` 不为空

---

## 步骤 5：生成反洗钱上报报文
- **方法**: POST
- **路径**: /api/aml/report/generate
- **请求体**:
  ```json
  {"caseId": "CASE-20260706-001", "reportType": "SUSPICIOUS_TRANSACTION"}
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - 返回报文 XML 内容，`$.data.reportXml` 不为空
  - 报文需包含 `<RptHead>` 和 `<RptBody>` 节点
  - 报文编号 `reportNo` 已生成

---

## 步骤 6：提交报文至反洗钱监测分析中心
- **方法**: POST
- **路径**: /api/aml/report/submit
- **请求体**:
  ```json
  {"reportNo": "{{步骤5.reportNo}}"}
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - `$.data.submitStatus` 为 `"SUBMITTED"`
  - 返回监管系统回执号 `$.data.ackNo`

---

## 步骤 7：查询报送回执——验证监管方已接收
- **方法**: GET
- **路径**: /api/aml/report/feedback?reportNo={{步骤5.reportNo}}
- **预期**:
  - 状态码: 200
  - `$.data.feedbackStatus` 属于 `["ACCEPTED", "RECEIVED", "PENDING"]`
  - 监管反馈时间 `$.data.feedbackTime` 不为空（若状态为 PENDING 则例外）

---

## 步骤 8：确认案例归档
- **方法**: PUT
- **路径**: /api/aml/case/archive
- **请求体**:
  ```json
  {"caseId": "CASE-20260706-001", "reportNo": "{{步骤5.reportNo}}"}
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - `$.data.caseStatus` 更新为 `"ARCHIVED"`

```

- [ ] **Step 2: 提交**

```bash
git add test-scenarios/aml-suspicious-report.md
git commit -m "feat: add AML suspicious transaction report example scenario

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 创建技能定义文件 `.claude/skills/biz-flow-test.md`

**Files:**
- Create: `.claude/skills/biz-flow-test.md`

**Interfaces:**
- Consumes: `api-env.yml`（通过 Read 工具）、`test-scenarios/*.md`（通过 Read 工具）
- Produces: 无代码级接口。技能通过 Read / Bash / Edit 工具与文件系统交互。分析变量依赖时提取 `{{步骤N.field}}` 引用关系；固化时通过 Edit 工具向场景文件追加 `**提取:** $.path → varName` 行。
- 外部命令依赖: `curl`（HTTP 调用）、`jq`（JSONPath 提取/断言）

- [ ] **Step 1: 创建技能目录并编写技能文件**

```bash
mkdir -p .claude/skills
```

然后创建文件 `.claude/skills/biz-flow-test.md`：

````markdown
---
name: biz-flow-test
description: Execute business flow API tests from Markdown scenario files
argument-hint: <scenario-name>
---

# 业务流程测试 /biz-test

对 `test-scenarios/` 下的 Markdown 场景文件执行 REST API 业务流程测试，顺序执行每个步骤、验证断言，并在全部通过后固化变量提取规则。

## 执行流程

### 参数解析

- `/biz-test <场景名>` — 执行 `test-scenarios/<场景名>.md`
- `/biz-test`（无参数）— 列出 `test-scenarios/` 下所有 `.md` 文件

### 步骤 0：加载配置

1. Read `api-env.yml`，解析以下字段：
   - `base_url`、`auth`（type / token / refresh）、`http`（timeout / retry）、`permission`
2. 若 `api-env.yml` 不存在，输出以下提示并终止：

```
❌ 未找到 api-env.yml，请先在项目根目录创建环境配置文件。

参考格式：
base_url: https://your-api.example.com
auth:
  type: bearer
  token: ${YOUR_TOKEN}
  refresh:
    enabled: true
    method: POST
    path: /api/auth/refresh
    token_field: $.data.token
http:
  timeout: 30000
  retry:
    max: 0
```

3. 展开 `auth.token` 中的 `${ENV_VAR}` 环境变量。若环境变量未设置，提示用户设置后重试。

### 步骤 1：加载场景文件

1. Read `test-scenarios/<name>.md`（若参数带了 `.md` 后缀则去除重复后缀）
2. 若文件不存在，列出 `test-scenarios/` 下所有 `.md` 文件：

```
❌ 未找到场景文件 "xxx.md"
可用的场景：
  - aml-suspicious-report  → test-scenarios/aml-suspicious-report.md
```

3. 解析场景文件结构：
   - `# 场景：<标题>` → 场景名称
   - `## 背景` → 业务背景（可选）
   - `## 前置条件` → 前置条件列表（可选，仅展示用）
   - `## 公共请求头` → 默认请求头（key: value，每行一个），变量引用暂保留
   - `## 步骤 N：<描述>` → 步骤分隔标记，提取步骤号 N 和描述
   - `- **方法**:` → HTTP 方法
   - `- **路径**:` → 请求路径（相对路径，拼接 base_url）
   - `- **请求头**:` → 步骤级请求头（覆盖公共请求头）
   - `- **请求体**:` → JSON 请求体（```json 代码块内）
   - `- **预期**:` → 断言列表，每条一行

### 步骤 2：解析变量依赖

对每个步骤的路径、请求头、请求体，扫描 `{{步骤N.字段路径}}` 和 `{{env.VAR}}` 引用：

- `{{步骤N.字段路径}}`：依赖第 N 个步骤的响应中某个字段值。若场景文件中已显式声明了该步骤的 `**提取:**` 行（格式为 `JSONPath → varName`），则执行时用 jq 精确提取。若未声明，由 AI 在步骤执行后的响应中智能推断需要提取的值。
- `{{env.VAR}}`：直接从环境变量 `${VAR}` 读取，若未设置则提示用户。

### 步骤 3：按序执行每个步骤

对每个步骤，执行以下子流程：

#### 3.1 构造请求

- 变量替换：将路径/请求头/请求体中的 `{{步骤N.field}}` 替换为已存储的变量值，`{{env.VAR}}` 替换为环境变量值
- URL = `base_url` + 路径
- 请求头合并：公共请求头（展开变量后） + 步骤请求头（覆盖同名字段）
- 若 `auth.type = bearer`，追加 `Authorization: Bearer <token>` 到请求头（若未显式覆盖）
- 若 `auth.type = cookie`，追加 `Cookie: <token>` 到请求头

#### 3.2 发起 HTTP 调用

构造 curl 命令并执行：

```bash
# 示例（POST with JSON body）
RESPONSE=$(curl -s -w "\n%{http_code}" \
  --max-time <http.timeout> \
  -X POST \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '<json_body>' \
  "<full_url>")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
```

- `--max-time` 使用 `http.timeout / 1000`（秒）
- `-s` 静默模式，`-w "\n%{http_code}"` 在末尾追加 HTTP 状态码
- 若 `retry.max > 0`，失败时按配置重试

#### 3.3 验证断言

对 `- **预期**:` 下每条断言逐条校验：

**精确断言（JSONPath + 期望值）：**
- 格式：`- \`$.field.path\` 为 \`"期望值"\``
- 用 jq 提取：`echo "$BODY" | jq -r '.field.path'`
- 将提取值与期望值严格比对（字符串/数字/布尔）
- 不匹配 → 输出差异并终止

**容许多值断言（属于列表）：**
- 格式：`- \`$.field\` 属于 \`["A", "B", "C"]\``
- 用 jq 提取实际值，检查是否在列表中
- 不在列表中 → 输出实际值并终止

**数值比较断言：**
- 格式：`- \`$.data.total\` > 0` 或 `- \`$.data.list\` 数组长度 > 0`
- 用 jq 提取值进行数值/长度比较
- 不满足 → 输出实际值并终止

**存在性断言：**
- 格式：`- \`$.data.reviewId\` 不为空`
- 用 jq 检查字段非 null 且非空字符串/空数组

**自然语言断言：**
- 非上述格式的断言行（如"返回订单对象，包含订单号和待支付状态"）
- AI 读取响应体，判断是否匹配语义描述
- 不匹配 → 输出 AI 判断的理由并终止

状态码断言：自动从 curl 输出的 `HTTP_CODE` 校验，与 `- 状态码: 200` 比对。不需要单独处理。

#### 3.4 步骤通过处理

- 记录步骤耗时（curl 开始到结束的时间差）
- 若该步骤仍有未显式提取的变量（后续步骤引用了 `{{步骤N.xxx}}` 但场景文件中未声明对应 `**提取:**`），由 AI 分析响应 JSON 结构，推断字段对应的 JSONPath，暂时记录在内存中（用于后续步骤变量替换）
- 提取方式：AI 查看当前步骤的响应 JSON，对于后续步骤引用的每个字段名（如 `orderId`、`reportNo`），在响应中搜索匹配的 key，确定其 JSONPath
- 继续下一步

#### 3.5 权限异常处理

**401 Unauthorized：**
1. 检查 `auth.refresh.enabled` 是否为 true
2. 若启用刷新：构造刷新请求（使用 `auth.refresh` 中的 method、path、body），发起调用
3. 从刷新响应中用 `auth.refresh.token_field` 的 JSONPath 提取新 Token
4. 刷新成功 → 更新内存中的 Token，用新 Token 重试当前步骤
5. 刷新失败 → 展示 `permission.prompt_template`，等待用户输入
6. 若未启用刷新 → 直接展示 `permission.prompt_template`

**403 Forbidden：**
1. 立即暂停，输出：

```
🚫 步骤 N "描述" 返回 403 Forbidden
可能原因：
  - Token 有效但权限不足（缺少所需角色/scope）
  - IP 地址不在白名单中
  - 账号被临时锁定
  - 接口需要额外授权（如审批流未完成）

当前 Token 的角色信息（若有）：<角色列表>
```

2. 展示 `permission.prompt_template`，等待用户选择 [1] 更新认证 / [2] 跳过 / [3] 终止

**其他 4xx/5xx：**
- 输出失败详情：步骤号、描述、HTTP 状态码、响应体（截取前 500 字符）
- 终止流程，打印已完成步骤的摘要

### 步骤 4：固化规则（仅在全部通过后执行）

全部步骤通过后，AI 对场景文件做以下更新（通过 Edit 工具）：

**4.1 补充变量提取规则：**
对每个步骤，若执行过程中 AI 推断出了变量依赖（如步骤2用了步骤1返回的 token，步骤6用了步骤5返回的 reportNo），在该步骤的 `- **预期**:` 区块之后追加显式提取声明：

```markdown
- **提取**:
  - `$.data.token` → token
  - `$.data.reportNo` → reportNo
```

如果已存在 `**提取:**` 区块，补充缺失的映射。

**4.2 补充精确断言：**
对每个步骤中"仅有自然语言断言，缺少相应 JSONPath 精确断言"的情况，在自然语言断言附近补充精确断言行。例如：

原始：
```
- 返回订单对象，包含订单号和待支付状态
```

补充为：
```
- `$.data.orderNo` 不为空
- `$.data.orderStatus` 为 `"PENDING_PAY"`
- 返回订单对象，包含订单号和待支付状态
```

### 步骤 5：输出测试报告

全部通过后，输出格式化报告：

```
═══════════════════════════════════════════
  业务流程测试报告
  场景：<标题>
  环境：<base_url>
  时间：<当前时间 YYYY-MM-DD HH:MM:SS>
  结果：✅ 全部通过 (X/X)
═══════════════════════════════════════════

  ✅ 步骤1 <描述>      <状态码>  (<耗时>s)
  ✅ 步骤2 <描述>      <状态码>  (<耗时>s) — <关键摘要>
  ...

  总耗时: <总秒数>s

  📝 本次固化：
    - 步骤N 补充提取规则 → `$.path.to.field` → fieldName
    - 步骤M 补充精确断言 → `$.path` 为 `"value"`

═══════════════════════════════════════════
```

- 关键摘要取每步最有辨识度的信息（如"找到 12 笔交易"、"reportNo: RPT20260706001"）
- 若无任何固化发生（场景已完备），省略 `📝 本次固化` 段落

## 边界情况处理

| 情况 | 处理 |
|------|------|
| 场景文件不存在 | 列出可用场景 |
| `api-env.yml` 不存在 | 提示创建并给出模板 |
| 变量引用无法解析（上一步未产生该字段） | 展示上一步响应体，提示用户指定 JSONPath |
| `{{env.VAR}}` 环境变量未设置 | 提示设置环境变量后重试 |
| curl 不可用 | 提示安装 curl |
| jq 不可用 | 提示安装 jq（`brew install jq` / `apt install jq`） |
| 响应体非合法 JSON | 直接输出原始响应用于 AI 判断，JSONPath 断言自动失败 |
| 请求体中包含 `{{步骤N.field}}` 但该字段值为 null/空 | 终止，提示用户该字段提取失败 |
| 场景文件无步骤（格式错误） | 提示用户参照示例场景文件检查格式 |
````

- [ ] **Step 2: 验证技能文件可被 Claude Code 识别**

```bash
# 检查技能文件存在且 frontmatter 格式正确
head -5 .claude/skills/biz-flow-test.md
```

期望输出包含 `---`、`name: biz-flow-test`、`description:`、`argument-hint:`。

- [ ] **Step 3: 提交**

```bash
git add .claude/skills/biz-flow-test.md
git commit -m "feat: add biz-flow-test skill for business flow API testing

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 验证整体项目结构

**Files:**
- Modify: 无（只读验证）

**Interfaces:**
- 无。纯验证任务。

- [ ] **Step 1: 确认文件树完整**

```bash
find . -type f \
  -not -path './.git/*' \
  -not -path './target/*' \
  -not -path './.idea/*' \
  -not -name 'HELP.md' \
  | sort
```

期望输出包含：
```
./.claude/skills/biz-flow-test.md
./api-env.yml
./test-scenarios/aml-suspicious-report.md
```

- [ ] **Step 2: 确认所有文件已提交**

```bash
git status
```

期望输出: `nothing to commit, working tree clean`

---

### Task 5: 功能验证 — 空参数执行（列出场景）

**Files:**
- 无修改

**Interfaces:**
- 验证技能可通过 `/biz-test`（无参数）列出 `test-scenarios/` 下的场景文件。

> **注意：** 此任务为手动验证，需要用户在 Claude Code 交互界面执行。

- [ ] **Step 1: 在 Claude Code 中执行 `/biz-test`（无参数）**

在 Claude Code 对话中输入：
```
/biz-test
```

- [ ] **Step 2: 验证输出**

期望：列出 `test-scenarios/` 下的所有 `.md` 文件，如：
```
可用的场景：
  - aml-suspicious-report  → test-scenarios/aml-suspicious-report.md
```

---

### Task 6: 功能验证 — 加载不存在的场景（错误处理）

> **注意：** 此任务为手动验证。

- [ ] **Step 1: 执行 `/biz-test nonexistent`**

在 Claude Code 对话中输入：
```
/biz-test nonexistent
```

- [ ] **Step 2: 验证错误提示**

期望：输出"未找到场景文件"并列出可用场景列表，而非系统错误。

---

### Task 7: 功能验证 — 加载场景并解析步骤（非真实 API 环境下的干跑验证）

> **注意：** 此任务为手动验证，验证技能可以正确解析场景文件结构。

- [ ] **Step 1: 执行 `/biz-test aml-suspicious-report`**

在 Claude Code 对话中输入：
```
/biz-test aml-suspicious-report
```

- [ ] **Step 2: 验证技能正确初始化**

期望输出（在步骤1执行前）应表明：
- 已加载 `api-env.yml`，解析出 `base_url`、`auth.type`、`http.timeout`
- 已加载场景文件，解析出 8 个步骤
- 识别出变量依赖关系（如步骤6引用 `{{步骤5.reportNo}}`）

> 由于 `api-env.yml` 中的 `base_url: https://aml-test.example.com` 并非真实环境，步骤 1 curl 调用会失败（DNS 解析失败或连接超时），这是预期的。重点是验证解析逻辑正确。

---

## 完成标准

- [x] `api-env.yml` 格式正确，YAML 语法通过
- [x] `test-scenarios/aml-suspicious-report.md` 包含完整 8 步反洗钱报送链路
- [x] `.claude/skills/biz-flow-test.md` 技能文件 frontmatter 格式正确
- [x] 所有文件已 git 提交
- [ ] `/biz-test` 空参数可列出场景（需手动验证）
- [ ] `/biz-test <不存在场景>` 给出友好错误提示（需手动验证）
- [ ] `/biz-test <存在的场景>` 可正确加载和解析步骤（需手动验证）
