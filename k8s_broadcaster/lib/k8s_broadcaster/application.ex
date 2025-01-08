defmodule K8sBroadcaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @version Mix.Project.config()[:version]

  @spec version() :: String.t()
  def version(), do: @version

  @spec cluster(:c0 | :c1 | :c2 | :c3) :: map()
  def cluster(name),
    do: Application.fetch_env!(:k8s_broadcaster, :cluster_info) |> Map.fetch!(name)

  @impl true
  def start(_type, _args) do
    dist_config =
      case Application.fetch_env!(:k8s_broadcaster, :dist_config) do
        nil ->
          nil

        config ->
          {Cluster.Supervisor, [[cluster: config], [name: K8sBroadcaster.ClusterSupervisor]]}
      end

    children =
      [
        K8sBroadcasterWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:k8s_broadcaster, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: K8sBroadcaster.PubSub},
        # Start to serve requests, typically the last entry
        dist_config,
        K8sBroadcaster.PeerSupervisor,
        K8sBroadcaster.Forwarder,
        K8sBroadcasterWeb.Endpoint,
        K8sBroadcasterWeb.Presence,
        {Task.Supervisor, name: K8sBroadcaster.TaskSupervisor}
      ]
      |> Enum.reject(&is_nil(&1))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: K8sBroadcaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    K8sBroadcasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
