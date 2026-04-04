---
name: github_skill
description: 从 GitHub 获取仓库信息，支持搜索热门项目、查询仓库详情。当需要查询 GitHub 项目信息时使用该技能。
---

# GitHub Skill

## 适用场景

当需要从 GitHub 获取以下信息时，使用该技能：

- 按语言搜索热门项目
- 查询特定仓库的详细信息
- 获取项目的 stars、forks、描述等

## 使用步骤

1. 确定查询类型（搜索或详情）。
2. 运行脚本 `node scripts/github.js <command> [args]`。运行之前 cd 到对应的目录。
3. 脚本将返回 JSON 格式的结果。

## 命令说明

### 搜索热门项目

```bash
node scripts/github.js search <language> [limit]
```

- `language`: 编程语言名称，如 `elixir`, `javascript`, `python`
- `limit`: 返回结果数量，默认 10

### 查询仓库详情

```bash
node scripts/github.js repo <owner>/<repo>
```

- `owner/repo`: 仓库全名，如 `phoenixframework/phoenix`

## 输出格式

- 搜索结果：JSON 数组，包含仓库名称、描述、stars、语言、URL 等
- 仓库详情：JSON 对象，包含完整仓库信息
- 若调用失败，将打印错误信息

## 示例

```bash
# 搜索 Elixir 热门项目
node scripts/github.js search elixir 10

# 搜索 JavaScript 热门项目
node scripts/github.js search javascript 5

# 查询 Phoenix 框架详情
node scripts/github.js repo phoenixframework/phoenix
```

## 注意事项

- 使用 GitHub 公开 API，有速率限制（每小时 60 次）
- 不需要认证即可使用基本功能
- 如需更高配额，可在脚本中配置 GitHub Token
