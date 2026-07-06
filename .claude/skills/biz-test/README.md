# biz-test — 业务流程测试技能

对 REST API 业务流程做端到端测试：描述调用链路 → 顺序执行 → 断言验证 → 固化沉淀。

## 快速开始

### 1. 安装

将整个目录复制到目标项目的 `.claude/skills/` 下：

```bash
cp -r .claude/skills/biz-test /path/to/your-project/.claude/skills/
```

前提条件：项目需安装 `curl` 和 `jq`。

### 2. 配置环境

编辑项目根目录的 `api-env.yml`（可复制下面的模板）：

```yaml
default: dev

environments:
  dev:
    base_url: https://dev-api.example.com
    auth:
      type: bearer
      token: ${DEV_TOKEN}
      refresh:
        enabled: true
        method: POST
        path: /api/auth/refresh
        token_field: $.data.token
    http:
      timeout: 30000
      retry:
        max: 0

  st:
    base_url: https://st-api.example.com
    auth:
      type: bearer
      token: ${ST_TOKEN}

  uat:
    base_url: https://uat-api.example.com
    auth:
      type: bearer
      token: ${UAT_TOKEN}

permission:
  prompt_template: |
    步骤 "{step_desc}" 返回了 {status_code}（{reason}）。
    [1] 输入新的认证信息
    [2] 跳过此步骤
    [3] 终止执行
```

设置 Token 环境变量：

```bash
export DEV_TOKEN="your-dev-token"
export ST_TOKEN="your-st-token"
```

### 3. 扫描接口

先看看项目有哪些接口可用：

```
/biz-test --scan
```

输出：

```
| 方法 | 路径                   | 类               | 类型       |
|------|-----------------------|------------------|-----------|
| POST | `/api/auth/login`     | AuthController   | controller |
| GET  | `/api/order/list`     | OrderController  | controller |
| POST | `/api/order/create`   | OrderController  | controller |
...
```

### 4. 编写场景

在 `test-scenarios/` 下创建 `.md` 文件：

```markdown
# 场景：订单创建与查询

## 背景
验证订单从创建到查询的完整链路。

## 前置条件
- 用户已注册且具备下单权限

## 公共请求头
Authorization: Bearer {{步骤1.token}}
Content-Type: application/json

---

## 步骤 1：登录获取 Token
- **方法**: POST
- **路径**: /api/auth/login
- **请求体**:
  ```json
  {"username": "testuser", "password": "{{env.TEST_PWD}}"}
  ```
- **预期**:
  - 状态码: 200
  - `$.code` 为 `"0000"`
  - 返回 Token，角色包含 `USER`

---

## 步骤 2：创建订单
- **方法**: POST
- **路径**: /api/order/create
- **请求体**:
  ```json
  {"title": "测试订单", "amount": 99.9}
  ```
- **预期**:
  - 状态码: 200
  - `$.data.orderNo` 不为空
  - `$.data.status` 为 `"PENDING_PAY"`

---

## 步骤 3：查询订单详情
- **方法**: GET
- **路径**: /api/order/detail?orderNo={{步骤2.orderNo}}
- **预期**:
  - 状态码: 200
  - `$.data.title` 为 `"测试订单"`
```

### 5. 执行

```
/biz-test order-create-flow --env dev
```

---

## 命令参考

| 命令 | 说明 |
|------|------|
| `/biz-test` | 列出所有场景文件 |
| `/biz-test <场景名>` | 执行场景（使用默认环境） |
| `/biz-test <场景名> --env st` | 指定环境执行 |
| `/biz-test --env list` | 列出所有可用环境 |
| `/biz-test --scan` | 扫描项目 API 接口 |

---

## 场景文件格式

```
# 场景：<标题>

## 背景            （可选）
## 前置条件          （可选）
## 公共请求头         （可选，所有步骤共用，支持变量引用）

## 步骤 N：<描述>
- **方法**: GET | POST | PUT | DELETE
- **路径**: /api/xxx
- **请求头**:         （可选，覆盖公共请求头）
- **请求体**:         （可选，```json 代码块）
- **预期**:
  - 状态码: 200
  - `$.field` 为 `"值"`           ← JSONPath 精确断言
  - `$.field` 属于 `["A","B"]`     ← 容许多值断言
  - `$.field` 不为空               ← 存在性断言
  - `$.data.count` > 0             ← 数值比较断言
  - 自然语言描述                    ← AI 辅助判断
- **提取**:           （执行通过后自动固化）
  - `$.data.id` → orderId
```

### 变量引用

| 语法 | 说明 | 示例 |
|------|------|------|
| `{{步骤N.field}}` | 引用前序步骤的返回值 | `{{步骤1.token}}`、`{{步骤2.orderNo}}` |
| `{{env.VAR}}` | 引用环境变量 | `{{env.TEST_PWD}}` |

首次执行时 AI 自动推断字段对应关系，全部通过后固化为 `**提取:**` 规则，后续直接精确提取。

---

## 文件结构

```
your-project/
├── api-env.yml                      # 多环境配置
├── test-scenarios/                  # 场景文件目录
│   ├── order-flow.md
│   └── user-register.md
└── .claude/skills/biz-test/
    ├── SKILL.md                     # 技能编排逻辑
    ├── README.md                    # 本文件
    ├── templates/
    │   ├── report.txt               # 报告模板
    │   ├── scenario-skeleton.md     # 场景骨架
    │   └── 403-forbidden.txt        # 403 错误模板
    └── scripts/
        ├── curl-exec.sh             # HTTP 请求执行
        └── api-scanner.sh           # API 接口扫描
```

---

## 断言类型

| 类型 | 写法 | 验证方式 |
|------|------|----------|
| 状态码 | `- 状态码: 200` | 精确比对 HTTP 状态码 |
| 精确断言 | `- \`$.code\` 为 \`"0000"\`` | jq JSONPath 严格比对 |
| 容许值 | `- \`$.status\` 属于 \`["A","B"]\`` | jq 提取 + 列表匹配 |
| 存在性 | `- \`$.data.id\` 不为空` | jq 检查非 null/非空 |
| 数值比较 | `- \`$.total\` > 0` | jq 提取 + 数值比较 |
| 自然语言 | `- 返回列表包含已创建订单` | AI 判断语义匹配 |

---

## 权限异常处理

| 状态码 | 行为 |
|--------|------|
| **401** | 若配置了 `auth.refresh`，自动刷新 Token 后重试；否则询问用户 |
| **403** | 展示可能原因和建议，等待用户选择：更新认证 / 跳过 / 终止 |
| **4xx/5xx** | 输出失败详情，终止流程 |

---

## 固化机制

场景首次执行通过后，技能自动更新场景文件：

1. **补充提取规则** — AI 推断的变量映射（如"步骤2 里的 orderNo 在 `$.data.orderNo`"）固化为 `**提取:**` 声明
2. **补充精确断言** — 自然语言断言（如"返回订单对象"）补充为 JSONPath 精确断言

后续执行不再依赖 AI 推断，直接使用固化规则，执行更快更稳定。
