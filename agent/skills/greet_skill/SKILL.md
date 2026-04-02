---
name: greet_skill
description: 根据提供的姓名打招呼，返回打招呼的文本。当需要根据文本描述打招呼时，使用该技能。
---

# Greet

## 适用场景

当需要根据文本描述打招呼时，使用该技能调用 `greet` 函数。

## 使用步骤

1. 准备清晰具体的 `name`。
2. 运行脚本 `node scripts/greet.js "<name>"`。运行之前cd到对应的目录。
3. 脚本将返回打招呼的文本。

## 输出格式

- 输出生成的打招呼文本。
- 若调用失败，将打印错误信息。

## 示例

```bash
node scripts/greet.js "张三"
```
