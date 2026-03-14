defmodule LightAgent.Core.LLM do
  require Logger

  @api_key Application.compile_env(:light_agent, Core.LLM)[:api_key]
  @base_url Application.compile_env(:light_agent, Core.LLM)[:base_url]
  @model Application.compile_env(:light_agent, Core.LLM)[:model]

  def call(messages, tools \\ []) do
    body = %{
      model: @model,
      messages: messages,
      tools: tools,
      temperature: 1
    }

    Logger.debug(
      "Calling LLM with request: #{Jason.encode!(body, pretty: true)}"
    )

    res =
      Req.post!(@base_url,
        json: body,
        headers: [
          {"Authorization", "Bearer #{@api_key}"}
        ],
        receive_timeout: 60000
      ).body

    Logger.debug("LLM Response: #{Jason.encode!(res, pretty: true)}")

    res
  end
end
