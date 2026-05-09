defmodule LightAgentWeb.Layouts do
  use Phoenix.Component

  def app(assigns) do
    ~H"""
    <%= @inner_content %>
    """
  end

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>LightAgent Dashboard</title>
        <link rel="stylesheet" href="/dashboard/css/dashboard.css" />
      </head>
      <body class="dashboard-page">
        <%= @inner_content %>
        <script defer src="/dashboard/js/phoenix.js"></script>
        <script defer src="/dashboard/js/phoenix_live_view.js"></script>
        <script defer src="/dashboard/js/app.js"></script>
      </body>
    </html>
    """
  end
end
