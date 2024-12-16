defmodule K8sBroadcasterWeb.Channel do
  @moduledoc false

  use K8sBroadcasterWeb, :channel

  alias K8sBroadcasterWeb.{Endpoint, Presence}

  @spec input_added(String.t()) :: :ok
  def input_added(id) do
    Endpoint.broadcast!("k8s_broadcaster:signaling", "input_added", %{id: id})
  end

  @spec input_removed(String.t()) :: :ok
  def input_removed(id) do
    Endpoint.broadcast!("k8s_broadcaster:signaling", "input_removed", %{id: id})
  end

  @impl true
  def join("k8s_broadcaster:signaling", _, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
    push(socket, "presence_state", Presence.list(socket))

    case K8sBroadcaster.Forwarder.get_input() do
      nil -> :ok
      input -> push(socket, "input_added", %{id: input.id})
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
end
