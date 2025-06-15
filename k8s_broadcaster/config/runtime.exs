import Config

read_region = fn ->
  case System.get_env("PHX_HOST") do
    nil -> nil
    host -> String.split(host, ".") |> List.first()
  end
end

read_cluster! = fn env ->
  case System.get_env(env) do
    nil ->
      %{reg: nil, url: nil, lat: nil, lng: nil}

    cluster ->
      [reg, url, lat, lng] = String.split(cluster, ";")
      %{reg: reg, url: url, lat: lat, lng: lng}
  end
end

read_ice_port_range! = fn ->
  case System.get_env("ICE_PORT_RANGE") do
    nil ->
      [0]

    raw_port_range ->
      case String.split(raw_port_range, "-", parts: 2) do
        [from, to] -> String.to_integer(from)..String.to_integer(to)
        _other -> raise "ICE_PORT_RANGE has to be in form of FROM-TO, passed: #{raw_port_range}"
      end
  end
end

read_k8s_dist_config! = fn ->
  case System.get_env("K8S_SERVICE_NAME") do
    nil ->
      raise "Distribution mode `k8s` requires setting the env variable K8S_SERVICE_NAME"

    service ->
      # For multi-cluster setup, we need to discover nodes across all clusters
      # using the MCS (Multi-Cluster Services) DNS names
      multi_cluster_services = [
        # Local cluster service
        "#{service}.default.svc.cluster.local",
        # Cross-cluster services via MCS
        "us-east5-broadcaster-headless.default.svc.clusterset.local",
        "europe-west9-broadcaster-headless.default.svc.clusterset.local",
        "asia-southeast1-broadcaster-headless.default.svc.clusterset.local"
      ]

      [
        strategy: K8sBroadcaster.MultiClusterDNSStrategy,
        config: [
          application_name: "k8s_broadcaster",
          services: multi_cluster_services,
          polling_interval: 5_000
        ]
      ]
  end
end

read_check_origin = fn ->
  case System.get_env("CHECK_ORIGIN") do
    nil -> true
    "true" -> true
    "false" -> false
    value -> String.split(value, ";")
  end
end

ice_server_config =
  %{
    urls: System.get_env("ICE_SERVER_URL") || "stun:stun.l.google.com:19302",
    username: System.get_env("ICE_SERVER_USERNAME"),
    credential: System.get_env("ICE_SERVER_CREDENTIAL")
  }
  |> Map.reject(fn {_k, v} -> is_nil(v) end)

ice_transport_policy =
  case System.get_env("ICE_TRANSPORT_POLICY") do
    "relay" -> :relay
    _other -> :all
  end

pc_config = [
  ice_servers: [ice_server_config],
  ice_transport_policy: ice_transport_policy,
  ice_port_range: read_ice_port_range!.()
]

# Cluster info is in form of %{reg: reg, url: url}.
# If not provided, %{reg: nil, url: nil} will be used
# and interpreted as using current window location
cluster_info =
  %{
    c0: read_cluster!.("C0"),
    c1: read_cluster!.("C1"),
    c2: read_cluster!.("C2"),
    c3: read_cluster!.("C3")
  }
  |> IO.inspect()

dist_config =
  case System.get_env("DISTRIBUTION_MODE") do
    "k8s" -> read_k8s_dist_config!.()
    _else -> nil
  end

config :k8s_broadcaster,
  region: read_region.(),
  cluster_info: cluster_info,
  pc_config: pc_config,
  dist_config: dist_config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/k8s_broadcaster start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :k8s_broadcaster, K8sBroadcasterWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :k8s_broadcaster, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :k8s_broadcaster, K8sBroadcasterWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: read_check_origin.()

  whip_token = System.get_env("WHIP_TOKEN") || raise "Environment variable WHIP_TOKEN is missing."

  admin_username =
    System.get_env("ADMIN_USERNAME") || raise "Environment variable ADMIN_USERNAME is missing."

  admin_password =
    System.get_env("ADMIN_PASSWORD") || raise "Environment variable ADMIN_PASSWORD is missing."

  config :k8s_broadcaster,
    whip_token: whip_token,
    admin_username: admin_username,
    admin_password: admin_password

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :k8s_broadcaster, K8sBroadcasterWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :k8s_broadcaster, K8sBroadcasterWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
