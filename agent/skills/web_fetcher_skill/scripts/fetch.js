const https = require("https");
const http = require("http");

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

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https:") ? https : http;

    const req = client.get(
      url,
      {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
          Accept:
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
          "Accept-Language": "en-US,en;q=0.5",
        },
        timeout: 30000,
      },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location
        ) {
          const redirectUrl = new URL(res.headers.location, url).toString();
          console.error(`Redirecting to: ${redirectUrl}`);
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
      },
    );

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Request timeout"));
    });
  });
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.log(`
Usage: node fetch.js <url> [format]

Arguments:
  url     - target URL (required)
  format  - output format: text (default) or html

Examples:
  node fetch.js "https://example.com"
  node fetch.js "https://example.com" html
`);
    process.exit(0);
  }

  const url = args[0];
  const format = args[1] || "text";

  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    console.error("Error: URL must start with http:// or https://");
    process.exit(1);
  }

  try {
    console.error(`Fetching: ${url}...`);
    const content = await fetchUrl(url);

    if (format === "html") {
      console.log(content);
    } else {
      const text = stripHtml(content);
      const maxLength = 5000;
      if (text.length > maxLength) {
        console.log(text.substring(0, maxLength));
        console.log(`\n... (content truncated, total ${text.length} chars)`);
      } else {
        console.log(text);
      }
    }
  } catch (error) {
    console.error(`Fetch failed: ${error.message}`);
    process.exit(1);
  }
}

main();
