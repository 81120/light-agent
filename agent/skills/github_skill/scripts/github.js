const https = require("https");

const GITHUB_API_BASE = "https://api.github.com";

// 通用的 HTTP GET 请求函数
function fetch(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      {
        headers: {
          "User-Agent": "light-agent-github-skill",
          Accept: "application/vnd.github.v3+json",
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try {
              resolve(JSON.parse(data));
            } catch (e) {
              reject(new Error(`JSON parse error: ${e.message}`));
            }
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.end();
  });
}

// 格式化数字（添加千位分隔符）
function formatNumber(num) {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// 截断字符串
function truncate(str, maxLength) {
  if (!str) return "";
  return str.length > maxLength ? str.substring(0, maxLength - 3) + "..." : str;
}

// 搜索热门项目
async function searchTopRepos(language, limit = 10) {
  const query = encodeURIComponent(`language:${language}`);
  const url = `${GITHUB_API_BASE}/search/repositories?q=${query}&sort=stars&order=desc&per_page=${limit}`;

  try {
    const result = await fetch(url);
    if (!result.items || result.items.length === 0) {
      console.log("未找到相关项目");
      return;
    }

    const repos = result.items;

    // 打印标题
    console.log(`\n${"=".repeat(80)}`);
    console.log(`  GitHub ${language.toUpperCase()} Top ${repos.length} 项目`);
    console.log(`${"=".repeat(80)}\n`);

    // 逐个打印项目信息
    repos.forEach((repo, index) => {
      const rank = (index + 1).toString().padStart(2, " ");
      const stars = formatNumber(repo.stargazers_count).padStart(8);
      const forks = formatNumber(repo.forks_count).padStart(7);

      console.log(`  ${rank}. ${repo.full_name}`);
      console.log(`      ${"⭐".repeat(Math.min(5, Math.ceil(repo.stargazers_count / 10000)))}`);
      console.log(`      Stars: ${stars}  |  Forks: ${forks}`);
      console.log(`      描述: ${truncate(repo.description, 70)}`);
      console.log(`      链接: ${repo.html_url}`);
      console.log();
    });

    console.log(`${"=".repeat(80)}`);
    console.log(`  数据来源: GitHub API  |  更新时间: ${new Date().toISOString().split("T")[0]}`);
    console.log(`${"=".repeat(80)}\n`);

  } catch (error) {
    console.error(`搜索失败: ${error.message}`);
    process.exit(1);
  }
}

// 获取仓库详情
async function getRepoDetails(ownerRepo) {
  if (!ownerRepo.includes("/")) {
    console.error("请使用格式: owner/repo");
    process.exit(1);
  }

  const [owner, repo] = ownerRepo.split("/");
  const url = `${GITHUB_API_BASE}/repos/${owner}/${repo}`;

  try {
    const result = await fetch(url);

    // 打印仓库详情
    console.log(`\n${"=".repeat(60)}`);
    console.log(`  ${result.full_name}`);
    console.log(`${"=".repeat(60)}\n`);

    console.log(`  描述: ${result.description || "No description"}`);
    console.log(`  主页: ${result.homepage || "N/A"}`);
    console.log();

    console.log(`  ⭐ Stars:      ${formatNumber(result.stargazers_count)}`);
    console.log(`  🍴 Forks:      ${formatNumber(result.forks_count)}`);
    console.log(`  👀 Watchers:   ${formatNumber(result.watchers_count)}`);
    console.log(`  🐛 Issues:     ${formatNumber(result.open_issues_count)}`);
    console.log();

    console.log(`  语言:         ${result.language || "Unknown"}`);
    console.log(`  许可证:       ${result.license ? result.license.spdx_id : "No license"}`);
    console.log();

    console.log(`  创建时间:     ${result.created_at.split("T")[0]}`);
    console.log(`  最后更新:     ${result.updated_at.split("T")[0]}`);
    console.log();

    console.log(`  GitHub:       ${result.html_url}`);
    console.log(`\n${"=".repeat(60)}\n`);

  } catch (error) {
    console.error(`获取仓库详情失败: ${error.message}`);
    process.exit(1);
  }
}

// 打印帮助信息
function printHelp() {
  console.log(`
GitHub Skill - 从 GitHub 获取仓库信息

用法:
  node github.js search <language> [limit]  搜索热门项目
  node github.js repo <owner/repo>          获取仓库详情

示例:
  node github.js search elixir 10           搜索 Elixir Top 10 项目
  node github.js search javascript 5        搜索 JavaScript Top 5 项目
  node github.js repo phoenixframework/phoenix  获取 Phoenix 框架详情

注意:
  - GitHub API 有速率限制（未认证 60 次/小时）
`);
}

// 主函数
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "-h" || args[0] === "--help") {
    printHelp();
    return;
  }

  const command = args[0];

  switch (command) {
    case "search":
      if (args.length < 2) {
        console.error("请提供语言名称: node github.js search <language> [limit]");
        process.exit(1);
      }
      const language = args[1];
      const limit = args[2] ? parseInt(args[2], 10) : 10;
      searchTopRepos(language, limit);
      break;

    case "repo":
      if (args.length < 2) {
        console.error("请提供仓库名称: node github.js repo <owner/repo>");
        process.exit(1);
      }
      getRepoDetails(args[1]);
      break;

    default:
      console.error(`未知命令: ${command}`);
      printHelp();
      process.exit(1);
  }
}

main();
