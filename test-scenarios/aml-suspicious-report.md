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
