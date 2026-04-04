---
name: skill_creator_skill
description: 帮助用户创建新的 skill 工具。通过交互式问答收集 skill 信息，自动生成 SKILL.md 和脚本模板。
---

# Skill Creator

## 适用场景

当需要创建新的 skill 时，使用该工具自动生成 skill 文件结构：

- 生成 SKILL.md 描述文档
- 生成脚本模板（支持 Node.js / Shell / Python）
- 自动创建目录结构

## 使用步骤

1. 确定新 skill 的基本信息：
   - Skill 名称
   - 功能描述
   - 实现方式（脚本语言）
   - 所需参数
2. 运行创建脚本 `node scripts/skill_creator.js create`。
3. 脚本会提示输入 skill 信息，确认后生成文件。

## 交互流程

脚本会依次询问：

1. **Skill 名称**：小写字母、下划线、连字符，如 `weather_skill`
2. **功能描述**：简短描述这个 skill 的用途
3. **脚本语言**：选择 Node.js / Shell / Python
4. **脚本命令**：脚本的主要命令名称（如 `weather`）
5. **参数列表**：需要的参数，用逗号分隔（如 `city, unit`）
6. **是否确认创建**

## 输出格式

创建成功后会在 `agent/skills/<skill_name>/` 目录下生成：

```
agent/skills/<skill_name>/
├── SKILL.md           # Skill 描述文档
└── scripts/
    └── <script_name>  # 脚本文件
```

## 示例

```bash
cd /Users/leo/code/erl/light-agent/agent/skills/skill_creator_skill
node scripts/skill_creator.js create
```

## 注意事项

- Skill 名称必须符合命名规范（小写字母、下划线、连字符）
- 如果目标 skill 已存在，会提示是否覆盖
- 生成的脚本是模板，需要根据实际需求补充实现逻辑
