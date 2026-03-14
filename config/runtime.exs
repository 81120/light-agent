import Config

if config_env() in [:dev, :test] do
  # 指定你的 .env 文件路径，通常放在项目根目录
  EnvLoader.load(".env")
end

config :light_agent, Core.LLM,
  api_key: System.get_env("API_KEY"),
  base_url: System.get_env("BASE_URL"),
  model: System.get_env("MODEL")
