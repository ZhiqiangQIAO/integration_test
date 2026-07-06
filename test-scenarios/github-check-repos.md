# 场景：查询 GitHub 仓库列表

## 背景
通过 GitHub REST API 查询指定用户的公开仓库列表，验证目标仓库是否存在。

## 前置条件
- GitHub API 公开访问，无需认证
- 目标仓库 `integration_test` 已创建

## 公共请求头
Accept: application/vnd.github+json
User-Agent: biz-flow-test

---

## 步骤 1：查询用户仓库列表
- **方法**: GET
- **路径**: /users/ZhiqiangQIAO/repos
- **预期**:
  - 状态码: 200
  - `$.` 数组长度 > 0
  - 返回仓库列表，其中包含 `integration_test` 仓库
- **提取**:
  - `$.[?(@.name=='integration_test')].full_name` → repoFullName
  - `$.[?(@.name=='integration_test')].html_url` → repoUrl
