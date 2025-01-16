defmodule K8sBroadcasterWeb.PageController do
  use K8sBroadcasterWeb, :controller

  require Logger

  def home(conn, _params) do
    render(conn, :home, page_title: "Home", current_url: current_url(conn))
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end

  def toggle_server_stream(conn, _params) do
    whip_token = Application.fetch_env!(:k8s_broadcaster, :whip_token)

    case Task.Supervisor.children(K8sBroadcaster.TaskSupervisor) do
      [] ->
        {:ok, _pid} =
          Task.Supervisor.start_child(
            K8sBroadcaster.TaskSupervisor,
            K8sBroadcaster.ServerStreamTask,
            :start,
            [conn, whip_token]
          )

      children ->
        Enum.each(children, fn pid -> K8sBroadcaster.ServerStreamTask.stop(pid) end)
    end

    conn
    |> resp(201, "")
    |> send_resp()
  end
end
