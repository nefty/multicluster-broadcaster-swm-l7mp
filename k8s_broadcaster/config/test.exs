import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :k8s_broadcaster, K8sBroadcasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "IZC4GPoi59CquGdP0YpCdEZx/+/2zpcbdySxdLhfrydB7tQS/ac1fAwYQ2AC0Kv3",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
