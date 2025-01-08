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

    Task.Supervisor.start_child(K8sBroadcaster.TaskSupervisor, fn ->
      Logger.info("Starting headless client")

      port =
        Port.open(
          {:spawn_executable, System.find_executable("node")},
          args: [Path.join(:code.priv_dir(:k8s_broadcaster), "headless_client.js")],
          env: [
            {~c"TOKEN", String.to_charlist(whip_token)},
            {~c"URL", String.to_charlist("#{conn.scheme}://#{conn.host}:#{conn.port}") |> dbg()}
          ]
        )

      Port.monitor(port)

      stream_receive(port)
    end)

    conn
    |> resp(201, "")
    |> send_resp()
  end

  def stop_server_stream(conn, _params) do
    Task.Supervisor.children(K8sBroadcaster.TaskSupervisor)
    |> Enum.each(fn pid ->
      send(pid, :exit)
    end)

    conn
    |> resp(201, "")
    |> send_resp()
  end

  defp stream_receive(port) do
    receive do
      :exit ->
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        Logger.info("Closing headless client")
        # For some reason, doing Port.close does not work
        System.shell("kill #{os_pid}")

      {:DOWN, _ref, :port, _, reason} ->
        Logger.info("Headless client exited with reason: #{inspect(reason)}")

      other ->
        dbg(other)
        stream_receive(port)
    end
  end
end
