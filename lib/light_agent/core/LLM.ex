defmodule LightAgent.Core.LLM do
  require Logger

  def call(messages, tools \\ []) do
    body = %{
      model: model(),
      messages: messages,
      tools: tools,
      temperature: 1
    }

    Logger.debug(
      "Calling LLM with request: #{Jason.encode!(body, pretty: true)}"
    )

    res =
      Req.post!(base_url(),
        json: body,
        headers: [
          {"Authorization", "Bearer #{api_key()}"}
        ],
        receive_timeout: 60000
      ).body

    Logger.debug("LLM Response: #{Jason.encode!(res, pretty: true)}")

    res
  end

  defp api_key do
    Application.fetch_env!(:light_agent, Core.LLM)[:api_key]
  end

  defp base_url do
    Application.fetch_env!(:light_agent, Core.LLM)[:base_url]
  end

  defp model do
    Application.fetch_env!(:light_agent, Core.LLM)[:model]
  end
end
