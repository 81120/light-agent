defmodule LightAgentWeb do
  def static_paths, do: ["dashboard"]

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :light_agent

      @session_options [
        store: :cookie,
        key: "_light_agent_key",
        signing_salt: "light-agent-salt"
      ]

      socket("/live", Phoenix.LiveView.Socket,
        websocket: [connect_info: [session: @session_options]],
        longpoll: false
      )

      plug(Plug.Static,
        at: "/",
        from: :light_agent,
        gzip: false,
        only: LightAgentWeb.static_paths()
      )

      plug(Plug.RequestId)
      plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

      plug(Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

      plug(Plug.MethodOverride)
      plug(Plug.Head)
      plug(Plug.Session, @session_options)
      plug(LightAgentWeb.Router)
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: LightAgentWeb.Layouts]

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {LightAgentWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      embed_templates("*")

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import Phoenix.HTML.Form
      import Phoenix.LiveView.Helpers

      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: LightAgentWeb.Endpoint,
        router: LightAgentWeb.Router,
        statics: LightAgentWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
