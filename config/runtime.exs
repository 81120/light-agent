import Config

if config_env() in [:dev, :test] do
  # 指定你的 .env 文件路径，通常放在项目根目录
  EnvLoader.load(".env")
end

config :light_agent, Core.LLM,
  api_key: System.get_env("API_KEY"),
  base_url: System.get_env("BASE_URL"),
  model: System.get_env("MODEL"),
  api_format: System.get_env("API_FORMAT", "chat_completions")

config :light_agent, LightAgentWeb.Endpoint,
  server: true,
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("PORT", "4000"))
  ],
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "light-agent-local-secret-key-base-light-agent-local-secret-key-base"
    )
