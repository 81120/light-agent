defmodule LightAgent.CLI.InputReader do
  @moduledoc false

  @escape <<27>>
  @backspace <<8>>
  @delete <<127>>

  def read_line(prompt, _history \\ [], opts \\ []) do
    case Keyword.fetch(opts, :basic_read_fun) do
      {:ok, basic_read_fun} ->
        basic_read(prompt, basic_read_fun)

      :error ->
        interactive_read(prompt, opts)
    end
  end

  defp basic_read(prompt, basic_read_fun) do
    basic_read_fun.(prompt)
  end

  defp interactive_read(prompt, opts) do
    io_getn_fun =
      Keyword.get(opts, :io_getn_fun, fn n -> IO.getn("", n) end)

    write_fun = Keyword.get(opts, :write_fun, &IO.write/1)

    write_fun.(prompt)
    prompt_line = prompt |> String.split("\n") |> List.last()

    do_read("", prompt_line, io_getn_fun, write_fun)
  end

  defp do_read(buffer, prompt_line, io_getn_fun, write_fun) do
    case io_getn_fun.(1) do
      :eof ->
        if buffer == "", do: nil, else: buffer <> "\n"

      "\n" ->
        write_fun.("\n")
        buffer <> "\n"

      "\r" ->
        write_fun.("\n")
        buffer <> "\n"

      @backspace ->
        next_buffer = delete_last_grapheme(buffer)
        redraw_line(prompt_line, next_buffer, write_fun)
        do_read(next_buffer, prompt_line, io_getn_fun, write_fun)

      @delete ->
        next_buffer = delete_last_grapheme(buffer)
        redraw_line(prompt_line, next_buffer, write_fun)
        do_read(next_buffer, prompt_line, io_getn_fun, write_fun)

      @escape ->
        consume_escape_sequence(io_getn_fun)
        do_read(buffer, prompt_line, io_getn_fun, write_fun)

      ch when is_binary(ch) ->
        next_buffer = buffer <> ch
        redraw_line(prompt_line, next_buffer, write_fun)
        do_read(next_buffer, prompt_line, io_getn_fun, write_fun)
    end
  end

  defp delete_last_grapheme(buffer) do
    graphemes = String.graphemes(buffer)

    case graphemes do
      [] -> ""
      _ -> graphemes |> Enum.drop(-1) |> Enum.join()
    end
  end

  defp redraw_line(prompt_line, buffer, write_fun) do
    write_fun.("\r\e[2K\e[0G" <> prompt_line <> buffer)
  end

  defp consume_escape_sequence(io_getn_fun) do
    case io_getn_fun.(1) do
      :eof -> :ok
      "[" -> consume_csi_tail(io_getn_fun, 8)
      _ -> :ok
    end
  end

  defp consume_csi_tail(_io_getn_fun, 0), do: :ok

  defp consume_csi_tail(io_getn_fun, remain) do
    case io_getn_fun.(1) do
      :eof -> :ok
      byte when byte in ["~", "A", "B", "C", "D", "F", "H"] -> :ok
      _ -> consume_csi_tail(io_getn_fun, remain - 1)
    end
  end
end
