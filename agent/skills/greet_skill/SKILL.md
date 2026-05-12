---
name: greet_skill
description: Generate a greeting message for a provided name. Use this skill when you need to produce greeting text from a name.
---

# Greet

## Use Cases

Use this skill to call `greet` when you need to generate greeting text from a provided name.

## Steps

1. Prepare a clear `name` value.
2. Run `node scripts/greet.js "<name>"` from this skill directory.
3. The script returns a greeting message.

## Output Format

- Success: generated greeting text.
- Failure: error message.

## Example

```bash
node scripts/greet.js "Alice"
```
