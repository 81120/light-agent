defmodule LightAgent.CLI.StatusFormatter do
  def format_status(kind, title, detail) do
    %{kind: kind, title: title, detail: detail}
  end

  def status_prefix(:success), do: "[SUCCESS]"
  def status_prefix(:warn), do: "[WARN]"
  def status_prefix(:error), do: "[ERROR]"
  def status_prefix(_), do: "[INFO]"

  def role_badge("assistant"), do: "[assistant]"
  def role_badge("user"), do: "[user]"
  def role_badge("system"), do: "[system]"
  def role_badge(other), do: "[#{other}]"

  def normalize_content(content) when is_binary(content) do
    content
    |> String.replace("\n", "\\n")
  end

  def normalize_content(content), do: inspect(content)
end
