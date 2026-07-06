---
name: biz-test
description: Execute business flow API tests from Markdown scenario files
argument-hint: <scenario-name> [--env <env>]
---

# 业务流程测试 /biz-test

对 `test-scenarios/` 下的 Markdown 场景文件执行 REST API 业务流程测试，顺序执行每个步骤、验证断言，并在全部通过后固化变量提取规则。

## 文件结构

```
.claude/skills/biz-test/
├── SKILL.md                          # 本文件 — 编排逻辑
├── templates/
│   ├── report.txt                    # 测试报告模板
│   ├── scenario-skeleton.md          # 新场景骨架模板
│   └── 403-forbidden.txt             # 403 错误输出模板
└── scripts/
    └── curl-exec.sh                  # curl 请求执行脚本
```

---

## 执行流程

### 参数解析

- `/biz-test <场景名> [--env <环境名>]` — 执行 `test-scenarios/<场景名>.md`
- `/biz-test --env list` — 列出 `api-env.yml` 中所有可用环境
- `/biz-test`（无参数）— 列出 `test-scenarios/` 下所有 `.md` 文件
- `--env` 不指定时使用 `api-env.yml` 中的 `default` 环境

### 步骤 0：加载配置

1. Read `api-env.yml`，解析结构：
   - `default` → 默认环境名
   - `environments` → 环境名 → { `base_url`, `auth`, `http` }
   - `permission` → 权限交互模板（所有环境共用）
2. 若 `api-env.yml` 不存在，提示用户创建并给出多环境配置示例。
3. 确定目标环境：
   - 若有 `--env <name>` 参数，使用 `environments.<name>`
   - 若 `--env list`，列出所有可用环境名并终止
   - 若无 `--env`，使用 `environments.<default>`
   - 若指定的环境名不存在，列出可用环境名并终止：

   ```
   ❌ 未找到环境 "prod"
   可用环境：
     - dev  → https://dev-api.example.com
     - st   → https://st-api.example.com
     - uat  → https://uat-api.example.com
     - github → https://api.github.com
   ```

4. 展开目标环境 `auth.token` 中的 `${ENV_VAR}` 环境变量。若未设置，提示用户设置后重试。
5. 若需要创建新场景，Read `templates/scenario-skeleton.md` 提供给用户。

### 步骤 1：加载场景文件

1. Read `test-scenarios/<name>.md`（若参数带 `.md` 后缀则去除）
2. 若文件不存在，列出 `test-scenarios/` 下所有 `.md` 文件并提示
3. 解析场景结构：
   - `# 场景：<标题>` → 场景名称
   - `## 背景` / `## 前置条件` → 可选，供展示
   - `## 公共请求头` → 默认请求头（key: value）
   - `## 步骤 N：<描述>` → 步骤分隔标记
   - `- **方法**:` / `- **路径**:` / `- **请求头**:` / `- **请求体**:` / `- **预期**:`
   - `- **提取**:` → 已有的显式 JSONPath 提取规则

### 步骤 2：解析变量依赖

扫描每个步骤的路径、请求头、请求体中的引用：
- `{{步骤N.字段路径}}`：若该步骤已有 `**提取:**` 声明则用 jq 精确提取；否则 AI 在响应中推断
- `{{env.VAR}}`：从环境变量读取，未设置则提示用户

### 步骤 3：按序执行每个步骤

#### 3.1 构造请求
- 变量替换：将 `{{步骤N.field}}` 替换为已存储值，`{{env.VAR}}` 替换为环境变量
- URL = `base_url` + 路径
- 请求头合并：公共请求头（展开变量后）+ 步骤级请求头（覆盖同名）
- 认证注入：`bearer` → `Authorization: Bearer <token>` | `cookie` → `Cookie: <token>` | `basic` → `-u <user>:<pass>` | `none` → 跳过

#### 3.2 发起 HTTP 调用

使用 `scripts/curl-exec.sh`：

```bash
# 用法: curl-exec.sh <method> <url> <timeout_ms> <retry_max> [headers...] [-d body]
# 输出: 三行 —— HTTP_CODE, DURATION_SEC, BODY
scripts/curl-exec.sh GET "https://api.example.com/path" 30000 0 \
  "Authorization: Bearer xxx" "Accept: application/json"
```

脚本自动处理：超时、5xx 重试（按 `retry.max`）、响应体/状态码分离、耗时统计。

#### 3.3 验证断言

对 `- **预期**:` 下每条断言逐一校验：

| 断言类型 | 格式 | 验证方式 |
|----------|------|----------|
| 状态码 | `- 状态码: 200` | 比对 `HTTP_CODE` |
| 精确断言 | `- \`$.path\` 为 \`"val"\`` | `jq -r '.path'` 严格比对 |
| 容许值 | `- \`$.path\` 属于 \`["A","B"]\`` | jq 提取值，检查是否在列表中 |
| 数值比较 | `- \`$.path\` > 0` | jq 提取值，数值/长度比较 |
| 存在性 | `- \`$.path\` 不为空` | jq 检查非 null 且非空 |
| 自然语言 | 非以上格式的文本 | AI 判断响应是否匹配语义 |

任一条断言不匹配 → 输出差异并终止。

#### 3.4 步骤通过处理
- 记录步骤耗时
- 若后续步骤引用了当前步骤的返回字段但场景中未声明 `**提取:**`，AI 分析响应 JSON 推断对应 JSONPath，暂存内存供后续步骤使用
- 继续下一步

#### 3.5 权限异常处理

**401 Unauthorized：**
1. 若 `auth.refresh.enabled = true`：用 `auth.refresh` 配置发起刷新请求，成功则更新 Token 并重试，失败则展示 `permission.prompt_template` 询问用户
2. 若未启用刷新：直接展示 `permission.prompt_template`

**403 Forbidden：**
Read `templates/403-forbidden.txt`，替换 `{{step_num}}`、`{{step_desc}}`、`{{role_info}}` 后输出，然后展示 `permission.prompt_template`，等待用户选择 [1]/[2]/[3]

**其他 4xx/5xx：**
输出失败详情：步骤号、描述、HTTP 状态码、响应体（前 500 字符），终止流程。

### 步骤 4：固化规则（仅在全部通过后执行）

全部步骤通过后，通过 Edit 工具更新场景文件：

**4.1 补充变量提取规则：**
对执行中 AI 推断出的变量依赖，在对应步骤的 `- **预期**:` 之后追加：
```markdown
- **提取**:
  - `$.data.token` → token
  - `$.data.reportNo` → reportNo
```
已有 `**提取:**` 区块则补充缺失映射。

**4.2 补充精确断言：**
对仅有自然语言断言的步骤，补充 JSONPath 精确断言。如：
`- 返回订单对象，包含订单号和待支付状态`
→ 补充 `- \`$.data.orderNo\` 不为空`、`- \`$.data.orderStatus\` 为 \`"PENDING_PAY"\``

### 步骤 5：输出测试报告

Read `templates/report.txt`，替换占位符后输出：
- `{{scenario_title}}`、`{{base_url}}`、`{{timestamp}}`
- `{{result_icon}}` / `{{result_summary}}` → ✅/❌ + 通过数/总数
- `{{#each steps}}` → 每步的 icon、step_num、description、status_code、duration、highlight
- `{{#if solidifications}}` → 本次新增的提取规则和精确断言列表（场景已完备则省略）

---

## 边界情况处理

| 情况 | 处理 |
|------|------|
| 场景文件不存在 | 列出可用场景 |
| `api-env.yml` 不存在 | 提示创建并给出模板 |
| 变量引用无法解析 | 展示上一步响应体，提示用户指定 JSONPath |
| `{{env.VAR}}` 未设置 | 提示设置环境变量后重试 |
| curl 不可用 | 提示安装 curl |
| jq 不可用 | 提示安装 jq（`brew install jq` / `apt install jq`） |
| 响应体非合法 JSON | 原始文本输出供 AI 判断，JSONPath 断言自动失败 |
| 变量值为 null/空 | 终止，提示用户该字段提取失败 |
| 场景文件格式错误 | 提示用户参照 `templates/scenario-skeleton.md` 检查格式 |
| 需要新建场景 | Read `templates/scenario-skeleton.md` 提供给用户作为起点 |