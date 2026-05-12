const readline = require("readline");
const fs = require("fs");
const path = require("path");

const SKILLS_DIR = path.join(__dirname, "..", "..");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function question(prompt) {
  return new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      resolve(answer.trim());
    });
  });
}

function validateSkillName(name) {
  const regex = /^[a-z][a-z0-9_-]*$/;
  if (!regex.test(name)) {
    return "Skill name must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and dashes";
  }
  return null;
}

function generateSkillMd(
  skillName,
  description,
  scriptLang,
  scriptCommand,
  params,
) {
  const paramsList = params.map((p) => `<${p}>`).join(" ");

  let runCommand = "";

  switch (scriptLang) {
    case "node":
      runCommand = `node scripts/${scriptCommand}.js ${paramsList}`;
      break;
    case "shell":
      runCommand = `bash scripts/${scriptCommand}.sh ${paramsList}`;
      break;
    case "python":
      runCommand = `python scripts/${scriptCommand}.py ${paramsList}`;
      break;
  }

  const paramsSection =
    params.length > 0
      ? `
## Parameters

${params.map((p) => `- \`${p}\`: TODO - add parameter description`).join("\n")}
`
      : "";

  return `---
name: ${skillName}
description: ${description}
---

# ${toTitleCase(skillName.replace(/_/g, " ").replace(/-/g, " "))}

## Use Cases

${description}

## Steps

1. TODO - add prerequisites.
2. Run \`${runCommand}\` from this skill directory.
3. The script returns execution output.
${paramsSection}## Output Format

- TODO - add output format details
- On failure, the script prints an error message.

## Example

\`\`\`bash
cd /path/to/light-agent/agent/skills/${skillName}
${runCommand.replace(/>/g, "_value")}
\`\`\`

## Notes

- TODO - add notes
`;

  function toTitleCase(str) {
    return str.replace(
      /\w\S*/g,
      (txt) => txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase(),
    );
  }
}

function generateNodeScript(skillName, scriptCommand, params) {
  const paramsCode = params
    .map((p, i) => `const ${p} = process.argv[${i + 2}];`)
    .join("\n");

  const paramsValidation = params
    .map(
      (p) => `if (!${p}) {
    console.error("Please provide ${p}");
    process.exit(1);
  }`,
    )
    .join("\n\n  ");

  const mainLogic =
    params.length > 0
      ? `console.log("Skill: ${skillName}");\n  console.log("Arguments: ${params.map((p) => `${p} = \${${p}}`).join(", ")}");\n  \n  // TODO: implement main logic`
      : `console.log("Skill: ${skillName}");\n  \n  // TODO: implement main logic`;

  return `const crypto = require("crypto");

function main() {
  ${params.length > 0 ? paramsCode + "\n\n  " + paramsValidation + "\n\n  " : ""}${mainLogic}
}

main();
`;
}

function generateShellScript(skillName, scriptCommand, params) {
  const paramsCheck = params
    .map(
      (p, i) => `if [ -z "\$${i + 1}" ]; then
  echo "Please provide ${p}"
  exit 1
fi`,
    )
    .join("\n\n");

  const paramsEcho = params.map((p, i) => `${p} = \$$[${i + 1}]`).join(", ");

  return `#!/bin/bash

${params.length > 0 ? paramsCheck + "\n\n" : ""}echo "Skill: ${skillName}"
${params.length > 0 ? `echo "Arguments: ${paramsEcho}"\n` : ""}# TODO: implement main logic
`;
}

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
        print("Please provide ${p}")
        sys.exit(1)`,
    )
    .join("\n\n");

  const mainLogic =
    params.length > 0
      ? `    print(f"Skill: ${skillName}")\n    print(f"Arguments: ${params.map((p) => `${p}={${p}}`).join(", ")}")\n    \n    # TODO: implement main logic`
      : `    print("Skill: ${skillName}")\n    \n    # TODO: implement main logic`;

  return `import sys

def main():
${params.length > 0 ? paramsCode + "\n\n" + paramsValidation + "\n\n" : "    "}${mainLogic}

if __name__ == "__main__":
    main()
`;
}

async function createSkill() {
  console.log("\n========================================");
  console.log("  Skill Creator - Create a New Skill");
  console.log("========================================\n");

  let skillName;
  while (true) {
    skillName = await question("Skill name (e.g. weather_skill): ");
    const error = validateSkillName(skillName);
    if (error) {
      console.log(`  ❌ ${error}\n`);
    } else {
      break;
    }
  }

  const description = await question("Description: ");

  console.log("\nScript language options:");
  console.log("  1. Node.js");
  console.log("  2. Shell (Bash)");
  console.log("  3. Python");
  let scriptLang;
  while (true) {
    const choice = await question("Choose script language [1-3]: ");
    const langMap = { 1: "node", 2: "shell", 3: "python" };
    if (langMap[choice]) {
      scriptLang = langMap[choice];
      break;
    }
    console.log("  ❌ Please enter 1, 2, or 3");
  }

  let scriptCommand;
  while (true) {
    scriptCommand = await question(
      `Script command name (default: ${skillName.replace(/_/g, "-")}): `,
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

  const paramsInput = await question(
    "Argument list (comma-separated, e.g. city,unit; optional): ",
  );
  const params = paramsInput
    ? paramsInput
        .split(",")
        .map((p) => p.trim())
        .filter((p) => p)
    : [];

  console.log("\n----------------------------------------");
  console.log("  Confirmation:");
  console.log("----------------------------------------");
  console.log(`  Skill name:      ${skillName}`);
  console.log(`  Description:     ${description}`);
  console.log(
    `  Script language: ${scriptLang === "node" ? "Node.js" : scriptLang === "shell" ? "Bash" : "Python"}`,
  );
  console.log(`  Script command:  ${scriptCommand}`);
  console.log(`  Arguments:       ${params.length > 0 ? params.join(", ") : "none"}`);
  console.log("----------------------------------------\n");

  const confirm = await question("Create this skill? [y/N]: ");
  if (confirm.toLowerCase() !== "y") {
    console.log("\n  Creation canceled.\n");
    rl.close();
    return;
  }

  const skillDir = path.join(SKILLS_DIR, skillName);
  const scriptsDir = path.join(skillDir, "scripts");

  if (fs.existsSync(skillDir)) {
    const overwrite = await question(
      `Skill "${skillName}" already exists. Overwrite? [y/N]: `,
    );
    if (overwrite.toLowerCase() !== "y") {
      console.log("\n  Creation canceled.\n");
      rl.close();
      return;
    }
  }

  fs.mkdirSync(scriptsDir, { recursive: true });

  const skillMdContent = generateSkillMd(
    skillName,
    description,
    scriptLang,
    scriptCommand,
    params,
  );
  const skillMdPath = path.join(skillDir, "SKILL.md");
  fs.writeFileSync(skillMdPath, skillMdContent);

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

  if (scriptLang === "shell") {
    fs.chmodSync(scriptPath, "755");
  }

  console.log("\n========================================");
  console.log("  ✅ Skill created successfully!");
  console.log("========================================\n");
  console.log(`  Location: ${skillDir}`);
  console.log("  Files:");
  console.log("    ├── SKILL.md");
  console.log("    └── scripts/");
  console.log(`        └── ${scriptCommand}.${scriptExt}`);
  console.log("\n  Next steps:");
  console.log("  1. Edit SKILL.md and add detailed guidance");
  console.log(`  2. Edit ${scriptCommand}.${scriptExt} and implement logic`);
  console.log(
    `  3. Test: cd ${skillDir} && node scripts/${scriptCommand}.${scriptExt} ${params.map((p) => `<${p}>`).join(" ")}`,
  );
  console.log();

  rl.close();
}

function printHelp() {
  console.log(`
Skill Creator - help you create new skills

Usage:
  node skill_creator.js create    Create a new skill interactively
  node skill_creator.js -h        Show help

Examples:
  node skill_creator.js create
`);
}

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
      console.error(`Unknown command: ${command}`);
      printHelp();
      process.exit(1);
  }
}

main();
