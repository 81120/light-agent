---
name: web_fetcher_skill
description: 从指定 URL 获取网页内容，支持纯文本提取和原始 HTML 获取。当需要从网站获取信息时使用该技能。
---

# Web Fetcher

## 适用场景

当需要从网页获取内容时，使用该技能：

- 获取新闻文章内容
- 抓取网页文本信息
- 获取 API 返回的 JSON 数据

## 使用步骤

1. 准备目标网页 URL。
2. 运行脚本 `node scripts/fetch.js <url> [format]`。
3. 脚本将返回网页内容。

## 命令说明

```bash
node scripts/fetch.js <url> [format]
```

- `url`: 目标网页地址（必需）
- `format`: 输出格式，可选 `text`（纯文本，默认）或 `html`（原始 HTML）

## 输出格式

- 成功：输出网页内容（纯文本或 HTML）
- 失败：输出错误信息

## 示例

```bash
# 获取网页纯文本内容
node scripts/fetch.js "https://example.com/article"

# 获取原始 HTML
node scripts/fetch.js "https://example.com" html

# 获取 API JSON 数据
node scripts/fetch.js "https://api.github.com/users/github"
```

## 注意事项

- 某些网站可能有反爬虫机制，无法获取内容
- 大型网页可能需要较长时间加载
- 仅支持 HTTP/HTTPS 协议
