defmodule K8sBroadcaster.MultiClusterDNSStrategy do
  @moduledoc """
  A custom libcluster strategy for discovering Elixir nodes across multiple
  GKE clusters using Multi-Cluster Services (MCS) DNS names.

  This strategy extends the basic Kubernetes DNS strategy to query multiple
  service endpoints across different clusters in the same fleet.
  """

  use Cluster.Strategy
  use GenServer

  alias Cluster.Strategy.State

  @default_polling_interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init([%State{} = state]) do
    {:ok, load(state), 0}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    handle_info(:load, state)
  end

  def handle_info(:load, %State{} = state) do
    {:noreply, load(state), polling_interval(state)}
  end

  def handle_info(_, state) do
    {:noreply, state, polling_interval(state)}
  end

  defp load(%State{topology: topology, connect: connect, disconnect: disconnect, list_nodes: list_nodes} = state) do
    new_nodelist =
      state.config
      |> get_services()
      |> get_nodes(state.config[:application_name])
      |> MapSet.new()

    # Ensure state.meta is a map, and get existing nodes or empty set
    current_meta = state.meta || %{}
    current_nodes = current_meta[:nodes] || MapSet.new()

    added = MapSet.difference(new_nodelist, current_nodes)
    removed = MapSet.difference(current_nodes, new_nodelist)

    new_nodelist
    |> MapSet.difference(MapSet.new([node()]))
    |> case do
      nodes when map_size(nodes) == 0 ->
        Cluster.Logger.warn(topology, "No nodes found")
      nodes ->
        Cluster.Logger.debug(topology, "Found nodes: #{inspect(MapSet.to_list(nodes))}")
    end

    Cluster.Strategy.connect_nodes(topology, connect, list_nodes, MapSet.to_list(added))
    Cluster.Strategy.disconnect_nodes(topology, disconnect, list_nodes, MapSet.to_list(removed))

    # Update meta with new node list, ensuring meta is always a map
    updated_meta = Map.put(current_meta, :nodes, new_nodelist)
    %{state | meta: updated_meta}
  end

  defp get_services(config) do
    services = config[:services] || []

    if Enum.empty?(services) do
      Cluster.Logger.warn(nil, "No services configured for multi-cluster discovery")
      []
    else
      services
    end
  end

  defp get_nodes(services, app_name) when is_list(services) do
    services
    |> Enum.flat_map(fn service ->
      get_nodes_for_service(service, app_name)
    end)
  end

  defp get_nodes_for_service(service, app_name) do
    case :inet_res.lookup(String.to_charlist(service), :in, :a) do
      {:error, reason} ->
        Cluster.Logger.warn(nil, "Failed to lookup A records for #{service}: #{inspect(reason)}")
        []

      ip_addresses ->
        # For headless services, we get individual pod IPs
        # We need to create node names from these IPs
        ip_addresses
        |> Enum.map(fn ip ->
          # Convert IP tuple to string
          ip_str = ip |> Tuple.to_list() |> Enum.join(".")
          :"#{app_name}@#{ip_str}"
        end)
        |> Enum.reject(&(&1 == node()))
    end
  rescue
    error ->
      Cluster.Logger.warn(nil, "Error getting nodes for service #{service}: #{inspect(error)}")
      []
  end

  defp polling_interval(%State{config: config}) do
    Keyword.get(config, :polling_interval, @default_polling_interval)
  end
end
