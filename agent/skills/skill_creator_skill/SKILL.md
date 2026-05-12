---
name: skill_creator_skill
description: Help users create new skills. Collect skill information through interactive prompts, then generate SKILL.md and script templates automatically.
---

# Skill Creator

## Use Cases

Use this skill to generate a new skill scaffold automatically:

- Generate `SKILL.md` documentation
- Generate script templates (Node.js / Shell / Python)
- Create directory structure

## Steps

1. Prepare basic skill information:
   - Skill name
   - Functional description
   - Implementation language
   - Required arguments
2. Run `node scripts/skill_creator.js create`.
3. Follow prompts and confirm creation.

## Interactive Flow

The script asks for:

1. **Skill name**: lowercase letters, underscores, and dashes, e.g. `weather_skill`
2. **Description**: short summary of what the skill does
3. **Script language**: Node.js / Shell / Python
4. **Script command**: primary command name (e.g. `weather`)
5. **Argument list**: comma-separated arguments (e.g. `city, unit`)
6. **Creation confirmation**

## Output Format

On success, it generates files under `agent/skills/<skill_name>/`:

```text
agent/skills/<skill_name>/
├── SKILL.md           # Skill documentation
└── scripts/
    └── <script_name>  # Script file
```

## Example

```bash
cd /Users/leo/code/erl/light-agent/agent/skills/skill_creator_skill
node scripts/skill_creator.js create
```

## Notes

- Skill names must follow naming rules (lowercase, underscore, dash)
- If the target skill exists, the script asks whether to overwrite
- Generated scripts are templates and should be completed for real use
