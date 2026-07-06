# 场景：<场景名称>

## 背景
<业务背景描述，可选>

## 前置条件
- <条件1>
- <条件2>

## 公共请求头
Authorization: Bearer {{步骤1.token}}
Content-Type: application/json
<其他场景级公共头>

---

## 步骤 1：<步骤描述>
- **方法**: GET | POST | PUT | DELETE
- **路径**: /api/xxx/yyy
- **请求头**:                           # 可选
  X-Custom-Header: value
- **请求体**:                           # 可选
  ```json
  {"key": "value"}
  ```
- **预期**:
  - 状态码: 200
  - `$.field` 为 `"精确值"`
  - 自然语言辅助验证描述

---

## 步骤 2：<步骤描述>
...