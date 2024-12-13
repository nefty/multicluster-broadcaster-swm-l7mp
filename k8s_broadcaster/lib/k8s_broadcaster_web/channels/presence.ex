defmodule K8sBroadcasterWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :k8s_broadcaster,
    pubsub_server: K8sBroadcaster.PubSub
end
