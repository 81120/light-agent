defmodule LightAgent.Core.SkillTest do
  use ExUnit.Case, async: true

  defmodule EchoSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:text, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:text])
      |> validate_required([:text])
    end

    def required_fields, do: [:text]
  end

  defmodule TestSkill do
    @moduledoc "test skill"
    use LightAgent.Core.Skill.CodeBasedSkill

    @doc "Echo input text"
    deftool(:echo, schema: EchoSchema)

    @impl true
    def exec(:echo, %{"text" => text}), do: text
  end

  test "code based skill exposes definition and executes" do
    definition = TestSkill.__skill_definition__()
    [tool] = definition.tools

    assert definition.name == "TestSkill"
    assert tool.name == :echo
    assert tool.description == "Echo input text"
    assert TestSkill.echo(%{"text" => "hi"}) == "hi"
  end

  test "runner builds tool schemas" do
    tool_names =
      LightAgent.Core.Skill.Runner.build_tools_schema()
      |> Enum.map(& &1.function.name)

    assert :get_location in tool_names
    assert :get_weather in tool_names
    assert :read_file in tool_names
    assert :run_command in tool_names
  end
end

defmodule LightAgent.Skills.FilesystemTest do
  use ExUnit.Case, async: true

  test "filesystem skill reads and writes files" do
    test_dir = Path.join(File.cwd!(), ".tmp_light_agent_tests")
    File.mkdir_p!(test_dir)

    path =
      Path.join(
        test_dir,
        "light_agent_test_#{System.unique_integer([:positive])}.txt"
      )

    assert LightAgent.Skills.Filesystem.exec(:write_file, %{
             "path" => path,
             "content" => "abc"
           }) ==
             "Successfully wrote file #{Path.expand(path)}"

    assert LightAgent.Skills.Filesystem.exec(:read_file, %{
             "path" => path
           }) ==
             "abc"
  end
end

defmodule LightAgent.Core.Skill.RunnerSecurityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias LightAgent.Core.Skill.Runner

  test "run_command requires confirmation and can be denied" do
    result =
      capture_io("n\n", fn ->
        [result] =
          Runner.handle_tool_call([
            %{
              "id" => "tool_1",
              "function" => %{
                "name" => "run_command",
                "arguments" => Jason.encode!(%{"command" => "echo hello"})
              }
            }
          ])

        send(self(), {:runner_result, result})
      end)

    assert is_binary(result)
    assert_receive {:runner_result, runner_result}
    assert runner_result.name == "run_command"

    {:ok, payload} = Jason.decode(runner_result.content)
    assert payload["type"] == "permission_denied"
    assert payload["tool"] == "run_command"
  end

  test "run_command requires confirmation and can be allowed" do
    _output =
      capture_io("y\n", fn ->
        [result] =
          Runner.handle_tool_call([
            %{
              "id" => "tool_2",
              "function" => %{
                "name" => "run_command",
                "arguments" => Jason.encode!(%{"command" => "echo hello"})
              }
            }
          ])

        send(self(), {:runner_result, result})
      end)

    assert_receive {:runner_result, result}
    assert result.name == "run_command"
    assert String.contains?(result.content, "hello")
  end

  test "read_file does not require confirmation" do
    test_dir = Path.join(File.cwd!(), ".tmp_light_agent_tests")
    File.mkdir_p!(test_dir)

    path =
      Path.join(
        test_dir,
        "light_agent_read_runner_#{System.unique_integer([:positive])}.txt"
      )

    :ok = File.write(path, "abc")

    [result] =
      Runner.handle_tool_call([
        %{
          "id" => "tool_3",
          "function" => %{
            "name" => "read_file",
            "arguments" => Jason.encode!(%{"path" => path})
          }
        }
      ])

    assert result.name == "read_file"
    assert result.content == "abc"
  end

  test "plan mode blocks tool execution" do
    [result] =
      Runner.handle_tool_call(
        [
          %{
            "id" => "tool_4",
            "function" => %{
              "name" => "run_command",
              "arguments" => Jason.encode!(%{"command" => "echo hello"})
            }
          }
        ],
        mode: :plan,
        plan_phase: :draft
      )

    assert result.name == "run_command"

    {:ok, payload} = Jason.decode(result.content)
    assert payload["type"] == "plan_mode_blocked"
    assert payload["tool"] == "run_command"
  end
end

defmodule LightAgent.CLI.CommandRouterPlanTest do
  use ExUnit.Case, async: true

  alias LightAgent.CLI.CommandRouter

  test "parses plan commands" do
    assert CommandRouter.parse("/plan on") == {:command, :plan, :on}
    assert CommandRouter.parse("/plan off") == {:command, :plan, :off}
    assert CommandRouter.parse("/plan apply") == {:command, :plan, :apply}
    assert CommandRouter.parse("/plan progress") == {:command, :plan, :progress}
    assert CommandRouter.parse("/plan") == {:command, :plan, :progress}
  end
end

defmodule LightAgent.Core.SessionServerPlanStateTest do
  use ExUnit.Case, async: false

  alias LightAgent.Core.SessionServer

  test "updates plan, apply starts first task, and progress reports totals" do
    session_id = "plan-test-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    :ok =
      GenServer.call(SessionServer.via_tuple(session_id), {:set_mode, :plan})

    :ok =
      GenServer.call(
        SessionServer.via_tuple(session_id),
        {:update_plan,
         %{
           "title" => "demo",
           "tasks" => [
             %{"text" => "step 1"},
             %{"id" => "T2", "text" => "step 2"}
           ]
         }}
      )

    plan = GenServer.call(SessionServer.via_tuple(session_id), :current_plan)
    assert plan["status"] == "drafting"
    assert plan["revision"] == 1
    assert Enum.map(plan["tasks"], & &1["id"]) == ["T1", "T2"]
    assert Enum.map(plan["tasks"], & &1["status"]) == ["pending", "pending"]

    assert :ok =
             GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

    progress =
      GenServer.call(SessionServer.via_tuple(session_id), :plan_progress)

    assert progress["status"] == "applying"
    assert progress["done"] == 0
    assert progress["total"] == 2
    assert hd(progress["tasks"])["status"] == "in_progress"

    GenServer.stop(pid)
  end

  test "advances subtask statuses on each tool-call turn while applying" do
    session_id = "plan-advance-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    :ok =
      GenServer.call(SessionServer.via_tuple(session_id), {:set_mode, :plan})

    :ok =
      GenServer.call(
        SessionServer.via_tuple(session_id),
        {:update_plan,
         %{
           "title" => "demo",
           "tasks" => [
             %{"id" => "T1", "text" => "step 1"},
             %{"id" => "T2", "text" => "step 2"}
           ]
         }}
      )

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)

    fake_request_fun = fn _body ->
      {:ok,
       %{
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "tool_calls" => [
                   %{
                     "id" => "tool_1",
                     "function" => %{
                       "name" => "read_file",
                       "arguments" => Jason.encode!(%{"path" => __ENV__.file})
                     }
                   }
                 ]
               }
             }
           ],
           "usage" => %{
             "prompt_tokens" => 1,
             "completion_tokens" => 1,
             "total_tokens" => 2
           }
         }
       }}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    try do
      assert :ok =
               GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

      assert {:running, _tool_results, _step_usage} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, "execute plan"},
                 30_000
               )

      progress1 =
        GenServer.call(SessionServer.via_tuple(session_id), :plan_progress)

      assert Enum.map(progress1["tasks"], & &1["status"]) == [
               "done",
               "in_progress"
             ]

      assert progress1["status"] == "applying"

      assert {:running, _tool_results, _step_usage} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, nil},
                 30_000
               )

      progress2 =
        GenServer.call(SessionServer.via_tuple(session_id), :plan_progress)

      assert Enum.map(progress2["tasks"], & &1["status"]) == ["done", "done"]
      assert progress2["status"] == "completed"
      assert progress2["done"] == 2
    after
      if prev_request_fun do
        Application.put_env(:light_agent, :llm_request_fun, prev_request_fun)
      else
        Application.delete_env(:light_agent, :llm_request_fun)
      end

      GenServer.stop(pid)
    end
  end

  test "captures plan JSON wrapped in markdown fence during drafting" do
    session_id = "plan-fenced-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)

    fenced_json =
      ~s|```json\n{"title":"demo","tasks":[{"id":"T1","text":"step 1"}]}\n```|

    fake_request_fun = fn _body ->
      {:ok,
       %{
         body: %{
           "choices" => [%{"message" => %{"content" => fenced_json}}],
           "usage" => %{
             "prompt_tokens" => 1,
             "completion_tokens" => 1,
             "total_tokens" => 2
           }
         }
       }}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    try do
      :ok =
        GenServer.call(SessionServer.via_tuple(session_id), {:set_mode, :plan})

      _ =
        GenServer.call(
          SessionServer.via_tuple(session_id),
          {:run_agent_step, "draft plan"}
        )

      plan = GenServer.call(SessionServer.via_tuple(session_id), :current_plan)
      assert plan["status"] == "ready"
      assert length(plan["tasks"]) == 1
    after
      if prev_request_fun do
        Application.put_env(:light_agent, :llm_request_fun, prev_request_fun)
      else
        Application.delete_env(:light_agent, :llm_request_fun)
      end

      GenServer.stop(pid)
    end
  end

  test "tool calls are not blocked after plan becomes completed" do
    session_id = "plan-completed-tools-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    :ok =
      GenServer.call(SessionServer.via_tuple(session_id), {:set_mode, :plan})

    :ok =
      GenServer.call(
        SessionServer.via_tuple(session_id),
        {:update_plan,
         %{
           "title" => "demo",
           "tasks" => [
             %{"id" => "T1", "text" => "step 1"}
           ]
         }}
      )

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)

    fake_request_fun = fn _body ->
      {:ok,
       %{
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "tool_calls" => [
                   %{
                     "id" => "tool_1",
                     "function" => %{
                       "name" => "read_file",
                       "arguments" => Jason.encode!(%{"path" => __ENV__.file})
                     }
                   }
                 ]
               }
             }
           ],
           "usage" => %{
             "prompt_tokens" => 1,
             "completion_tokens" => 1,
             "total_tokens" => 2
           }
         }
       }}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    try do
      assert :ok =
               GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

      assert {:running, _tool_results_1, _usage_1} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, "execute"},
                 30_000
               )

      progress =
        GenServer.call(SessionServer.via_tuple(session_id), :plan_progress)

      assert progress["status"] == "completed"

      assert {:running, tool_results_2, _usage_2} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, nil},
                 30_000
               )

      [result] = tool_results_2
      assert result.name == "read_file"
      assert is_binary(result.content)
      assert String.starts_with?(result.content, "defmodule")
    after
      if prev_request_fun do
        Application.put_env(:light_agent, :llm_request_fun, prev_request_fun)
      else
        Application.delete_env(:light_agent, :llm_request_fun)
      end

      GenServer.stop(pid)
    end
  end

  test "apply_plan rejects empty plan" do
    session_id = "plan-empty-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    assert {:error, :empty_plan} =
             GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

    GenServer.stop(pid)
  end
end

defmodule LightAgent.Core.LLMFormatTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.LLM

  test "builds chat completions payload" do
    request_fun = fn body ->
      send(self(), {:request_body, body})
      {:ok, %{body: %{"choices" => []}}}
    end

    assert {:ok, _} =
             LLM.call(
               [%{role: "user", content: "hello"}],
               [],
               request_fun: request_fun,
               api_format: :chat_completions
             )

    assert_receive {:request_body, body}
    assert Map.has_key?(body, :messages)
    refute Map.has_key?(body, :input)
  end

  test "builds responses payload when api_format is responses" do
    request_fun = fn body ->
      send(self(), {:request_body, body})
      {:ok, %{body: %{"choices" => []}}}
    end

    tools = [
      %{
        type: "function",
        function: %{
          name: :read_file,
          description: "Read file",
          parameters: %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}}
          }
        }
      }
    ]

    assert {:ok, _} =
             LLM.call(
               [%{role: "user", content: "hello"}],
               tools,
               request_fun: request_fun,
               api_format: :responses
             )

    assert_receive {:request_body, body}
    assert Map.has_key?(body, :input)
    refute Map.has_key?(body, :messages)

    assert [response_tool] = body[:tools]
    assert response_tool[:type] == "function"
    assert response_tool[:name] == "read_file"
    refute Map.has_key?(response_tool, :function)
  end

  test "maps assistant tool calls and tool outputs for responses input" do
    request_fun = fn body ->
      send(self(), {:request_body, body})
      {:ok, %{body: %{"choices" => []}}}
    end

    messages = [
      %{role: "user", content: "hello"},
      %{
        role: "assistant",
        tool_calls: [
          %{
            "id" => "tool_1",
            "function" => %{
              "name" => "read_file",
              "arguments" => Jason.encode!(%{"path" => "./x"})
            }
          }
        ]
      },
      %{role: "tool", tool_call_id: "tool_1", content: "ok"}
    ]

    assert {:ok, _} =
             LLM.call(
               messages,
               [],
               request_fun: request_fun,
               api_format: :responses
             )

    assert_receive {:request_body, body}
    assert is_list(body[:input])

    assert Enum.any?(body[:input], fn item ->
             item["type"] == "function_call" and item["call_id"] == "tool_1"
           end)

    assert Enum.any?(body[:input], fn item ->
             item["type"] == "function_call_output" and
               item["call_id"] == "tool_1" and item["output"] == "ok"
           end)

    refute Enum.any?(body[:input], fn item -> item["role"] == "tool" end)
  end
end

defmodule LightAgent.Core.SessionServerResponsesFormatTest do
  use ExUnit.Case, async: false

  alias LightAgent.Core.SessionServer

  test "parses responses api text output" do
    session_id = "responses-text-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)
    prev_llm_config = Application.get_env(:light_agent, Core.LLM)

    test_pid = self()

    fake_request_fun = fn body ->
      send(test_pid, {:request_body, body})

      {:ok,
       %{
         body: %{
           "output" => [
             %{
               "type" => "message",
               "content" => [
                 %{"type" => "output_text", "text" => "responses ok"}
               ]
             }
           ],
           "usage" => %{
             "prompt_tokens" => 1,
             "completion_tokens" => 1,
             "total_tokens" => 2
           }
         }
       }}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    Application.put_env(
      :light_agent,
      Core.LLM,
      Keyword.put(prev_llm_config || [], :api_format, :responses)
    )

    try do
      assert {:done, "responses ok", _step_usage} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, "hello"},
                 30_000
               )

      assert_receive {:request_body, body}
      assert Map.has_key?(body, :input)
      refute Map.has_key?(body, :messages)
    after
      restore_request_fun(prev_request_fun)
      restore_llm_config(prev_llm_config)
      GenServer.stop(pid)
    end
  end

  test "parses responses api function call output" do
    session_id = "responses-tool-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)
    prev_llm_config = Application.get_env(:light_agent, Core.LLM)

    fake_request_fun = fn _body ->
      {:ok,
       %{
         body: %{
           "output" => [
             %{
               "type" => "function_call",
               "id" => "tool_1",
               "name" => "read_file",
               "arguments" => %{"path" => __ENV__.file}
             }
           ],
           "usage" => %{
             "prompt_tokens" => 1,
             "completion_tokens" => 1,
             "total_tokens" => 2
           }
         }
       }}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    Application.put_env(
      :light_agent,
      Core.LLM,
      Keyword.put(prev_llm_config || [], :api_format, :responses)
    )

    try do
      assert {:running, tool_results, _step_usage} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, "execute"},
                 30_000
               )

      [result] = tool_results
      assert result.name == "read_file"
      assert String.starts_with?(result.content, "defmodule")
    after
      restore_request_fun(prev_request_fun)
      restore_llm_config(prev_llm_config)
      GenServer.stop(pid)
    end
  end

  test "returns fallback message for invalid responses payload" do
    session_id = "responses-invalid-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    prev_request_fun = Application.get_env(:light_agent, :llm_request_fun)
    prev_llm_config = Application.get_env(:light_agent, Core.LLM)

    fake_request_fun = fn _body ->
      {:ok, %{body: %{"output" => []}}}
    end

    Application.put_env(:light_agent, :llm_request_fun, fake_request_fun)

    Application.put_env(
      :light_agent,
      Core.LLM,
      Keyword.put(prev_llm_config || [], :api_format, :responses)
    )

    try do
      assert {:done, "LLM returned an invalid response. Please try again later.", _step_usage} =
               GenServer.call(
                 SessionServer.via_tuple(session_id),
                 {:run_agent_step, "hello"},
                 30_000
               )
    after
      restore_request_fun(prev_request_fun)
      restore_llm_config(prev_llm_config)
      GenServer.stop(pid)
    end
  end

  defp restore_request_fun(nil),
    do: Application.delete_env(:light_agent, :llm_request_fun)

  defp restore_request_fun(request_fun),
    do: Application.put_env(:light_agent, :llm_request_fun, request_fun)

  defp restore_llm_config(nil),
    do: Application.delete_env(:light_agent, Core.LLM)

  defp restore_llm_config(config),
    do: Application.put_env(:light_agent, Core.LLM, config)
end
