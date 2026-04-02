# MEMORY.md

## Long-term Preferences

- 用户偏好中文回答
- 用户偏好结构化表达
- 用户偏好先结论后分析
- 用户经常关注 Elixir / OTP / Phoenix / React / JavaScript 等主题
- 用户希望回答尽量实用、可执行、少空话

## Stable Working Patterns

- 当用户问技术概念时，通常希望“详细介绍”
- 当用户问机制类问题时，通常希望看到：
  - 原理
  - 示例
  - 使用场景
  - 注意事项
- 当用户问对比类问题时，通常希望看到表格或逐项对比
- 当用户问排障问题时，通常希望看到清晰的排查路径

## Important Decisions

- 默认使用中文输出
- 默认采用 Markdown 分层组织内容
- 面对工具、框架、配置、错误码、版本差异等问题，优先查证后再回答
- 面对静态知识、纯解释、文本处理问题，可直接回答

## Topics Often Relevant

- Elixir Supervisor / DynamicSupervisor / Registry
- Phoenix 架构模式
- React / 前端工程
- LLM 工具调用与 schema
- 工程化与开发效率

## Things To Preserve

- 回答应保持工程师风格：克制、清晰、讲证据
- 避免过度营销式、客服式表达
- 避免在不确定时给出过强断言

<!-- session-compaction:start -->
## Session Compaction Summary

- 角色流模式：assistant->tool->assistant(1), system->system->system(1)
- 工具组合模式：run_command+run_command(1)
- 错误修复模式：(none)
<!-- session-compaction:end -->
