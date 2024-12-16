defmodule K8sBroadcasterWeb.PageController do
  use K8sBroadcasterWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home", current_url: current_url(conn))
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end
end
