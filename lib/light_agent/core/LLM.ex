defmodule LightAgent.Core.LLM do
  require Logger

  @default_max_attempts 3
  @default_retry_delay_ms 200

  def call(messages, tools \\ [], opts \\ []) do
    body = %{
      model: model(),
      messages: messages,
      tools: tools,
      temperature: 1
    }

    request_fun = Keyword.get(opts, :request_fun, &default_request/1)

    max_attempts =
      Keyword.get(opts, :max_attempts, @default_max_attempts)

    retry_delay_ms =
      Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)

    do_call_with_retry(
      body,
      request_fun,
      max_attempts,
      retry_delay_ms,
      1
    )
  end

  defp do_call_with_retry(
         body,
         request_fun,
         max_attempts,
         retry_delay_ms,
         attempt
       ) do
    log_json_debug("Calling LLM with request", body)

    case safe_request(request_fun, body) do
      {:ok, res} ->
        log_json_debug("LLM Response", res.body)
        {:ok, res.body}

      {:error, reason} ->
        if attempt < max_attempts do
          Logger.warning(
            "LLM 调用失败，开始第 #{attempt + 1} 次重试，原因: #{inspect(reason)}"
          )

          Process.sleep(retry_delay_ms)

          do_call_with_retry(
            body,
            request_fun,
            max_attempts,
            retry_delay_ms,
            attempt + 1
          )
        else
          Logger.error("LLM 调用失败，达到最大重试次数，原因: #{inspect(reason)}")

          {:error, :request_failed, "LLM 调用失败，请稍后重试。"}
        end
    end
  end

  defp safe_request(request_fun, body) do
    try do
      case request_fun.(body) do
        {:ok, res} ->
          {:ok, res}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_result, other}}
      end
    rescue
      e ->
        {:error, {:exception, e}}
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp default_request(body) do
    Req.post(base_url(),
      json: body,
      headers: [
        {"Authorization", "Bearer #{api_key()}"}
      ],
      receive_timeout: 300_000
    )
  end

  defp log_json_debug(prefix, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, encoded} ->
        Logger.debug("#{prefix}: #{encoded}")

      {:error, reason} ->
        Logger.debug("#{prefix}: <json encode failed: #{inspect(reason)}>")
    end
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
