const https = require("https");
const http = require("http");

// 简单的 HTML 标签移除函数
function stripHtml(html) {
  return html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, " ")
    .trim();
}

// 获取网页内容
function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https:") ? https : http;
    
    const req = client.get(
      url,
      {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
          "Accept-Language": "en-US,en;q=0.5",
        },
        timeout: 30000,
      },
      (res) => {
        // 处理重定向
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          const redirectUrl = new URL(res.headers.location, url).toString();
          console.error(`重定向到: ${redirectUrl}`);
          fetchUrl(redirectUrl).then(resolve).catch(reject);
          return;
        }

        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode}: ${res.statusMessage}`));
          return;
        }

        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => resolve(data));
      }
    );

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("请求超时"));
    });
  });
}

// 主函数
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.log(`
用法: node fetch.js <url> [format]

参数:
  url     - 目标网页地址（必需）
  format  - 输出格式: text（默认）或 html

示例:
  node fetch.js "https://example.com"
  node fetch.js "https://example.com" html
`);
    process.exit(0);
  }

  const url = args[0];
  const format = args[1] || "text";

  // 验证 URL
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    console.error("错误: URL 必须以 http:// 或 https:// 开头");
    process.exit(1);
  }

  try {
    console.error(`正在获取: ${url}...`);
    const content = await fetchUrl(url);
    
    if (format === "html") {
      console.log(content);
    } else {
      const text = stripHtml(content);
      // 限制输出长度，避免过长
      const maxLength = 5000;
      if (text.length > maxLength) {
        console.log(text.substring(0, maxLength));
        console.log(`\n... (内容已截断，共 ${text.length} 字符)`);
      } else {
        console.log(text);
      }
    }
  } catch (error) {
    console.error(`获取失败: ${error.message}`);
    process.exit(1);
  }
}

main();
