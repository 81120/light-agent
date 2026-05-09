defmodule LightAgentWeb.Router do
  use LightAgentWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {LightAgentWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", LightAgentWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/dashboard", DashboardLive, :index)
  end
end
