---
name: web_fetcher_skill
description: Fetch web content from a URL, supporting plain-text extraction and raw HTML output. Use this skill when you need to retrieve information from websites.
---

# Web Fetcher

## Use Cases

Use this skill when you need web content:

- Fetch news article content
- Extract text from webpages
- Retrieve JSON from API endpoints

## Steps

1. Prepare the target URL.
2. Run `node scripts/fetch.js <url> [format]`.
3. The script returns webpage content.

## Command

```bash
node scripts/fetch.js <url> [format]
```

- `url`: target URL (required)
- `format`: output format, `text` (default) or `html`

## Output Format

- Success: webpage content (text or HTML)
- Failure: error message

## Examples

```bash
# Fetch page text content
node scripts/fetch.js "https://example.com/article"

# Fetch raw HTML
node scripts/fetch.js "https://example.com" html

# Fetch API JSON response
node scripts/fetch.js "https://api.github.com/users/github"
```

## Notes

- Some websites may block scraping
- Large pages may take longer to fetch
- Only HTTP/HTTPS is supported
