defmodule K8sBroadcasterWeb.PageController do
  use K8sBroadcasterWeb, :controller

  require Logger

  def home(conn, _params) do
    render(conn, :home, page_title: "Home", current_url: current_url(conn))
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end

  def start_server_stream(conn, _params) do
    whip_token = Application.fetch_env!(:k8s_broadcaster, :whip_token)

    {:ok, _pid} =
      Task.Supervisor.start_child(
        K8sBroadcaster.TaskSupervisor,
        K8sBroadcaster.ServerStreamTask,
        :start,
        [conn, whip_token]
      )

    conn
    |> resp(201, "")
    |> send_resp()
  end

  def stop_server_stream(conn, _params) do
    K8sBroadcaster.TaskSupervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid -> K8sBroadcaster.ServerStreamTask.stop(pid) end)

    conn
    |> resp(201, "")
    |> send_resp()
  end
end
