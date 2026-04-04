import Config

config :light_agent, :agent_external_root, "agent"

config :light_agent, LightAgent.Core.Scheduler,
  jobs: [
    # 每15分钟执行一次（Cron 语法）
    {"*/15 * * * * *",
     {LightAgent.Core.SessionMemoryCompactor, :do_compact_all_sessions, []}}
  ]
