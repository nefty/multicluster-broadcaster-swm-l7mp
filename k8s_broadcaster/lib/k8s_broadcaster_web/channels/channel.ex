defmodule K8sBroadcasterWeb.Channel do
  @moduledoc false

  use K8sBroadcasterWeb, :channel

  alias K8sBroadcasterWeb.{Endpoint, Presence}

  @spec input_added(K8sBroadcaster.Forwarder.input_spec()) :: :ok
  def input_added(input) do
    Endpoint.broadcast!("k8s_broadcaster:signaling", "input_added", %{
      id: input.id,
      region: input.region
    })
  end

  @spec input_removed(String.t()) :: :ok
  def input_removed(id) do
    Endpoint.broadcast!("k8s_broadcaster:signaling", "input_removed", %{id: id})
  end

  @impl true
  def join("k8s_broadcaster:signaling", _, socket) do
    send(self(), :after_join)
    {:ok, %{labels: get_labels()}, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
    push(socket, "presence_state", Presence.list(socket))

    case K8sBroadcaster.Forwarder.get_input() do
      nil -> :ok
      input -> push(socket, "input_added", %{id: input.id, region: input.region})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("packet_loss", payload, socket) do
    case K8sBroadcaster.PeerSupervisor.fetch_pid(payload["resourceId"]) do
      {:ok, pid} -> K8sBroadcaster.Forwarder.set_packet_loss(pid, payload["value"])
      _ -> :ok
    end

    {:noreply, socket}
  end

  defp get_labels() do
    # converts cluster_info into labels that are ready
    # to be displayed on the globe
    Application.fetch_env!(:k8s_broadcaster, :cluster_info)
    |> Map.take([:c1, :c2, :c3])
    |> Enum.map(fn {_key, cluster} ->
      %{text: cluster.reg, type: "cluster", lat: cluster.lat, lng: cluster.lng}
    end)
    # filter incorrect data
    |> Enum.reject(fn label -> label.lat == nil or label.lng == nil end)
  end
end
