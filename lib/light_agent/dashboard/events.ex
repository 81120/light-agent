defmodule LightAgent.Dashboard.Events do
  @sessions_topic "dashboard:sessions"
  @global_context_topic "dashboard:global_context"

  def sessions_topic, do: @sessions_topic
  def global_context_topic, do: @global_context_topic

  def session_topic(session_id) when is_binary(session_id) do
    "dashboard:session:" <> session_id
  end

  def subscribe_sessions do
    Phoenix.PubSub.subscribe(LightAgent.PubSub, @sessions_topic)
  end

  def subscribe_global_context do
    Phoenix.PubSub.subscribe(LightAgent.PubSub, @global_context_topic)
  end

  def subscribe_session(session_id) when is_binary(session_id) do
    Phoenix.PubSub.subscribe(LightAgent.PubSub, session_topic(session_id))
  end

  def unsubscribe_session(session_id) when is_binary(session_id) do
    Phoenix.PubSub.unsubscribe(LightAgent.PubSub, session_topic(session_id))
  end

  def broadcast_sessions_changed(event \\ :updated, payload \\ %{}) do
    broadcast(@sessions_topic, %{
      scope: :sessions,
      event: event,
      payload: payload
    })
  end

  def broadcast_session_updated(session_id, event \\ :updated, payload \\ %{})
      when is_binary(session_id) do
    broadcast(session_topic(session_id), %{
      scope: :session,
      session_id: session_id,
      event: event,
      payload: payload
    })
  end

  def broadcast_global_context_updated(payload \\ %{}) do
    broadcast(@global_context_topic, %{
      scope: :global_context,
      event: :updated,
      payload: payload
    })
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(
      LightAgent.PubSub,
      topic,
      {:dashboard_event, topic, message}
    )
  end
end
