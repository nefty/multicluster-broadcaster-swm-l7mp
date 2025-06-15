# K8sBroadcaster

A simple, distributed (spread across multiple nodes), WHIP/WHEP streaming service.

Distribution is implemented using [Distributed Erlang](https://www.erlang.org/doc/system/distributed.html). Audio and video packets are sent between nodes using TCP. Connection between client and server is a casual WebRTC connection.

This is a modified version of Elixir WebRTC [Broadcaster app](https://github.com/elixir-webrtc/apps/tree/master/broadcaster). Modifications include:

* support for Kubernetes distribution mode
* removal of multistream feature
* UI adjustments

## Run locally

To start the app locally:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment variables

K8sBroadcaster can be configured using the following environment variables:

* `PHX_HOST` - domain name under which this app will be available. It's used to generate URLs throughout the app, and its first part is used to determine app's region. E.g. `poland.broadcaster.stunner.cc` denotes that this specific instance is running in Poland.
* `CHECK_ORIGIN` - whether to check the origin of requests. Can be `true`, `false` or a list of hosts that are allowed. If `true`, origin is checked against `PHX_HOST`. Wildcards are supported. See [here](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-common-configuration) for more.
* `PORT` - port the HTTP endpoint will listen to.
* `SECRET_KEY_BASE` - a secret key used as a base to generate secrets for encrypting and signing data. It has to be 64 bytes long. You can generate one with `mix phx.gen.secret`.
* `DISTRIBUTION_MODE` - how Erlang nodes should connect to each other. Can be `none` or `k8s`.
* `K8S_SERVICE_NAME` - service name that will be looked up for other Erlang nodes.
* `C1`, `C2`, `C3` - clusters information. Should be in form of "CLUSTER_NAME;CLUSTER_URL;CLUSTER_LAT;CLUSTER_LNG". E.g. "USWEST;https://us-west.broadcaster.stunner.cc/;45;-122". It's used for UI button labels, connection information and globe visualization.
* `C0`- should be in form of "GLOBAL;URL" where URL is the domain name that can be used to establish connection to the geographically closest cluster.
* `ICE_PORT_RANGE` - port range that server side peer connection will use to establish ICE connection.
* `ICE_SERVER_URL` - STUN/TURN server URL. When running using Kubernetes, this should be Stunner URL. Used both by the client and server side.
* `ICE_SERVER_USERNAME` - TURN server username.
* `ICE_SERVER_CREDENTIAL` - TURN server password.
* `ICE_TRANSPORT_POLICY` - ICE tranport policy. Defaults to `all`. Can be set to `relay`. Used by the client side.
* `WHIP_TOKEN` - token needed to stream into the app.
* `ADMIN_USERNAME` - username to the admin panel.
* `ADMIN_PASSWORD` - password to the admin panel.
