defmodule K8sBroadcaster.ServerStreamTask do
  require Logger

  def start(conn, whip_token) do
    Logger.info("Starting headless client")

    port =
      Port.open(
        {:spawn_executable, System.find_executable("node")},
        [
          :binary,
          args: [Path.join(:code.priv_dir(:k8s_broadcaster), "headless_client.js")],
          env: [
            {~c"TOKEN", String.to_charlist(whip_token)},
            {~c"URL", String.to_charlist("#{conn.scheme}://#{conn.host}:#{conn.port}")}
          ]
        ]
      )

    Port.monitor(port)

    receive_messages(port)
  end

  def stop(pid) do
    send(pid, :exit)
  end

  defp receive_messages(port) do
    receive do
      :exit ->
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        Logger.info("Closing headless client")
        # For some reason, doing Port.close does not work
        System.shell("kill #{os_pid}")

      {:DOWN, _ref, :port, _, reason} ->
        Logger.info("Headless client exited with reason: #{inspect(reason)}")

      {^port, {:data, data}} ->
        Logger.info(String.trim("[Headless client]: #{data}"))
        receive_messages(port)
    end
  end
end
