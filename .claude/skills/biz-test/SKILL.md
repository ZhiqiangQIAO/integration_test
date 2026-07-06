---
name: biz-test
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
- 若 `auth.type = basic`，追加 `-u <username>:<password>` 到 curl 命令
- 若 `auth.type = none`，不注入任何认证头

#### 3.2 发起 HTTP 调用

构造 curl 命令并执行：

```bash
# 示例（POST with JSON body）
RESPONSE=$(curl -s -w "\n%{http_code}" \
  --max-time $((http.timeout / 1000)) \
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
