const readline = require("readline");
const fs = require("fs");
const path = require("path");

const SKILLS_DIR = path.join(__dirname, "..", "..");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

// 提问函数
function question(prompt) {
  return new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      resolve(answer.trim());
    });
  });
}

// 验证 skill 名称
function validateSkillName(name) {
  const regex = /^[a-z][a-z0-9_-]*$/;
  if (!regex.test(name)) {
    return "Skill 名称必须以小写字母开头，只能包含小写字母、数字、下划线和连字符";
  }
  return null;
}

// 生成 SKILL.md 内容
function generateSkillMd(
  skillName,
  description,
  scriptLang,
  scriptCommand,
  params,
) {
  const paramsList = params.map((p) => `<${p}>`).join(" ");
  const paramsExample = params.map((p) => `["${p}_value"]`).join(" ");

  let runCommand = "";
  let langHint = "";

  switch (scriptLang) {
    case "node":
      runCommand = `node scripts/${scriptCommand}.js ${paramsList}`;
      langHint = "Node.js";
      break;
    case "shell":
      runCommand = `bash scripts/${scriptCommand}.sh ${paramsList}`;
      langHint = "Bash";
      break;
    case "python":
      runCommand = `python scripts/${scriptCommand}.py ${paramsList}`;
      langHint = "Python";
      break;
  }

  const paramsSection =
    params.length > 0
      ? `
## 参数说明

${params.map((p) => `- \`${p}\`: TODO - 补充参数说明`).join("\n")}
`
      : "";

  return `---
name: ${skillName}
description: ${description}
---

# ${toTitleCase(skillName.replace(/_/g, " ").replace(/-/g, " "))}

## 适用场景

${description}

## 使用步骤

1. TODO - 补充前置条件。
2. 运行脚本 \`${runCommand}\`。运行之前 cd 到对应的目录。
3. 脚本将返回执行结果。
${paramsSection}
## 输出格式

- TODO - 补充输出格式说明
- 若调用失败，将打印错误信息。

## 示例

\`\`\`bash
cd /path/to/light-agent/agent/skills/${skillName}
${runCommand.replace(/>/g, "_value")}
\`\`\`

## 注意事项

- TODO - 补充注意事项
`;

  function toTitleCase(str) {
    return str.replace(
      /\w\S*/g,
      (txt) => txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase(),
    );
  }
}

// 生成 Node.js 脚本模板
function generateNodeScript(skillName, scriptCommand, params) {
  const paramsCode = params
    .map((p, i) => `const ${p} = process.argv[${i + 2}];`)
    .join("\n");

  const paramsValidation = params
    .map(
      (p) => `if (!${p}) {
    console.error("请提供 ${p}");
    process.exit(1);
  }`,
    )
    .join("\n\n  ");

  const mainLogic =
    params.length > 0
      ? `console.log("Skill: ${skillName}");\n  console.log("参数: ${params.map((p) => `${p} = \${${p}}`).join(", ")}");\n  \n  // TODO: 实现主要逻辑`
      : `console.log("Skill: ${skillName}");\n  \n  // TODO: 实现主要逻辑`;

  return `const crypto = require("crypto");

function main() {
  ${params.length > 0 ? paramsCode + "\n\n  " + paramsValidation + "\n\n  " : ""}${mainLogic}
}

main();
`;
}

// 生成 Shell 脚本模板
function generateShellScript(skillName, scriptCommand, params) {
  const paramsCheck = params
    .map(
      (p, i) => `if [ -z "\$${i + 1}" ]; then
  echo "请提供 ${p}"
  exit 1
fi`,
    )
    .join("\n\n");

  const paramsEcho = params.map((p, i) => `${p} = \$$[${i + 1}]`).join(", ");

  return `#!/bin/bash

${params.length > 0 ? paramsCheck + "\n\n" : ""}echo "Skill: ${skillName}"
${params.length > 0 ? `echo "参数: ${paramsEcho}"\n` : ""}
# TODO: 实现主要逻辑
`;
}

// 生成 Python 脚本模板
function generatePythonScript(skillName, scriptCommand, params) {
  const paramsCode = params
    .map(
      (p, i) =>
        `    ${p} = sys.argv[${i + 1}] if len(sys.argv) > ${i + 1} else None`,
    )
    .join("\n");

  const paramsValidation = params
    .map(
      (p) => `    if not ${p}:
        print("请提供 ${p}")
        sys.exit(1)`,
    )
    .join("\n\n");

  const mainLogic =
    params.length > 0
      ? `    print(f"Skill: ${skillName}")\n    print(f"参数: ${params.map((p) => `${p}={${p}}`).join(", ")}")\n    \n    # TODO: 实现主要逻辑`
      : `    print("Skill: ${skillName}")\n    \n    # TODO: 实现主要逻辑`;

  return `import sys

def main():
${params.length > 0 ? paramsCode + "\n\n" + paramsValidation + "\n\n" : "    "}${mainLogic}

if __name__ == "__main__":
    main()
`;
}

// 主创建流程
async function createSkill() {
  console.log("\n========================================");
  console.log("  Skill Creator - 创建新的 Skill");
  console.log("========================================\n");

  // 1. 收集 Skill 名称
  let skillName;
  while (true) {
    skillName = await question("Skill 名称 (如 weather_skill): ");
    const error = validateSkillName(skillName);
    if (error) {
      console.log(`  ❌ ${error}\n`);
    } else {
      break;
    }
  }

  // 2. 收集功能描述
  const description = await question("功能描述: ");

  // 3. 选择脚本语言
  console.log("\n脚本语言选项:");
  console.log("  1. Node.js");
  console.log("  2. Shell (Bash)");
  console.log("  3. Python");
  let scriptLang;
  while (true) {
    const choice = await question("选择脚本语言 [1-3]: ");
    const langMap = { 1: "node", 2: "shell", 3: "python" };
    if (langMap[choice]) {
      scriptLang = langMap[choice];
      break;
    }
    console.log("  ❌ 请输入 1、2 或 3");
  }

  // 4. 脚本命令名称
  let scriptCommand;
  while (true) {
    scriptCommand = await question(
      `脚本命令名称 (默认: ${skillName.replace(/_/g, "-")}): `,
    );
    if (!scriptCommand) {
      scriptCommand = skillName.replace(/_/g, "-");
    }
    const error = validateSkillName(scriptCommand);
    if (error) {
      console.log(`  ❌ ${error}`);
    } else {
      break;
    }
  }

  // 5. 参数列表
  const paramsInput = await question(
    "参数列表 (用逗号分隔，如 city,unit，可留空): ",
  );
  const params = paramsInput
    ? paramsInput
        .split(",")
        .map((p) => p.trim())
        .filter((p) => p)
    : [];

  // 6. 确认信息
  console.log("\n----------------------------------------");
  console.log("  确认信息:");
  console.log("----------------------------------------");
  console.log(`  Skill 名称:   ${skillName}`);
  console.log(`  功能描述:     ${description}`);
  console.log(
    `  脚本语言:     ${scriptLang === "node" ? "Node.js" : scriptLang === "shell" ? "Bash" : "Python"}`,
  );
  console.log(`  脚本命令:     ${scriptCommand}`);
  console.log(
    `  参数列表:     ${params.length > 0 ? params.join(", ") : "无"}`,
  );
  console.log("----------------------------------------\n");

  const confirm = await question("确认创建? [y/N]: ");
  if (confirm.toLowerCase() !== "y") {
    console.log("\n  已取消创建。\n");
    rl.close();
    return;
  }

  // 7. 创建文件
  const skillDir = path.join(SKILLS_DIR, skillName);
  const scriptsDir = path.join(skillDir, "scripts");

  // 检查是否已存在
  if (fs.existsSync(skillDir)) {
    const overwrite = await question(
      `Skill "${skillName}" 已存在，是否覆盖? [y/N]: `,
    );
    if (overwrite.toLowerCase() !== "y") {
      console.log("\n  已取消创建。\n");
      rl.close();
      return;
    }
  }

  // 创建目录
  fs.mkdirSync(scriptsDir, { recursive: true });

  // 生成 SKILL.md
  const skillMdContent = generateSkillMd(
    skillName,
    description,
    scriptLang,
    scriptCommand,
    params,
  );
  const skillMdPath = path.join(skillDir, "SKILL.md");
  fs.writeFileSync(skillMdPath, skillMdContent);

  // 生成脚本
  let scriptContent;
  let scriptExt;
  switch (scriptLang) {
    case "node":
      scriptContent = generateNodeScript(skillName, scriptCommand, params);
      scriptExt = "js";
      break;
    case "shell":
      scriptContent = generateShellScript(skillName, scriptCommand, params);
      scriptExt = "sh";
      break;
    case "python":
      scriptContent = generatePythonScript(skillName, scriptCommand, params);
      scriptExt = "py";
      break;
  }

  const scriptPath = path.join(scriptsDir, `${scriptCommand}.${scriptExt}`);
  fs.writeFileSync(scriptPath, scriptContent);

  // 设置脚本权限（Shell）
  if (scriptLang === "shell") {
    fs.chmodSync(scriptPath, "755");
  }

  // 8. 输出结果
  console.log("\n========================================");
  console.log("  ✅ Skill 创建成功!");
  console.log("========================================\n");
  console.log(`  创建位置: ${skillDir}`);
  console.log(`  文件列表:`);
  console.log(`    ├── SKILL.md`);
  console.log(`    └── scripts/`);
  console.log(`        └── ${scriptCommand}.${scriptExt}`);
  console.log("\n  下一步:");
  console.log(`  1. 编辑 SKILL.md 补充详细说明`);
  console.log(`  2. 编辑 ${scriptCommand}.${scriptExt} 实现具体逻辑`);
  console.log(
    `  3. 测试脚本: cd ${skillDir} && node scripts/${scriptCommand}.${scriptExt} ${params.map((p) => `<${p}>`).join(" ")}`,
  );
  console.log();

  rl.close();
}

// 打印帮助
function printHelp() {
  console.log(`
Skill Creator - 帮助创建新的 Skill

用法:
  node skill_creator.js create    交互式创建新 skill
  node skill_creator.js -h        显示帮助信息

示例:
  node skill_creator.js create
`);
}

// 主函数
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "-h" || args[0] === "--help") {
    printHelp();
    process.exit(0);
  }

  const command = args[0];

  switch (command) {
    case "create":
      createSkill();
      break;
    default:
      console.error(`未知命令: ${command}`);
      printHelp();
      process.exit(1);
  }
}

main();
