defmodule K8sBroadcaster.Forwarder do
  @moduledoc false

  use GenServer

  require Logger

  alias Phoenix.PubSub

  alias ExWebRTC.PeerConnection
  alias ExWebRTC.RTP.H264
  alias ExWebRTC.RTP.Munger

  alias K8sBroadcaster.PeerSupervisor
  alias K8sBroadcasterWeb.Channel

  @pubsub K8sBroadcaster.PubSub
  # Timeout for removing input/outputs that fail to connect
  @connect_timeout_s 15
  @connect_timeout_ms @connect_timeout_s * 1000

  @type id :: String.t()

  @type input_spec :: %{
          pc: pid(),
          id: id(),
          video: String.t() | nil,
          audio: String.t() | nil,
          available_layers: [String.t()] | nil
        }

  @type output_spec :: %{
          video: String.t() | nil,
          audio: String.t() | nil,
          munger: Munger.t(),
          packet_loss: non_neg_integer(),
          layer: String.t() | nil,
          pending_layer: String.t() | nil
        }

  @type state :: %{
          # WHIP
          pending_input: input_spec() | nil,
          local_input: input_spec() | nil,
          remote_inputs: %{pid() => input_spec()},

          # WHEP
          pending_outputs: MapSet.t(pid()),
          outputs: %{pid() => output_spec()}
        }

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec set_layer(pid(), String.t()) :: :ok | :error
  def set_layer(pc, layer) do
    GenServer.call(__MODULE__, {:set_layer, pc, layer})
  end

  @spec get_layers() :: {:ok, [String.t()] | nil} | :error
  def get_layers() do
    GenServer.call(__MODULE__, :get_layers)
  end

  @spec connect_input(pid(), id()) :: :ok
  def connect_input(pc, id) do
    GenServer.call(__MODULE__, {:connect_input, id, pc})
  end

  @spec connect_output(pid(), id()) :: :ok
  def connect_output(pc, input_id) do
    GenServer.call(__MODULE__, {:connect_output, input_id, pc})
  end

  @spec get_input() :: input_spec() | nil
  def get_input() do
    GenServer.call(__MODULE__, :get_input)
  end

  @spec get_local_input() :: input_spec() | nil
  def get_local_input() do
    GenServer.call(__MODULE__, :get_local_input)
  end

  @spec set_packet_loss(pid(), non_neg_integer()) :: :ok
  def set_packet_loss(pc, value) do
    GenServer.cast(__MODULE__, {:set_packet_loss, pc, value})
  end

  @impl true
  def init(_arg) do
    state = %{
      pending_input: nil,
      local_input: nil,
      remote_input: nil,
      pending_outputs: MapSet.new(),
      outputs: %{}
    }

    {:ok, state, {:continue, :after_init}}
  end

  @impl true
  def handle_continue(:after_init, state) do
    # Get remote inputs already present in cluster
    Node.list()
    |> :erpc.multicall(__MODULE__, :get_local_input, [], 5000)
    |> case do
      input when is_map(input) -> send(self(), {:input_added, input})
      _ -> :ok
    end

    PubSub.subscribe(@pubsub, "inputs")

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_input, _from, state) do
    {:reply, state.local_input || state.remote_input, state}
  end

  @impl true
  def handle_call(:get_local_input, _from, state) do
    {:reply, state.local_input, state}
  end

  @impl true
  def handle_call({:set_layer, pc, layer}, _from, state) do
    with {:ok, output} <- Map.fetch(state.outputs, pc),
         input when not is_nil(input) <- state.local_input || state.remote_input,
         true <- input.available_layers != nil,
         true <- layer in input.available_layers do
      output = %{output | pending_layer: layer}
      state = %{state | outputs: Map.put(state.outputs, pc, output)}

      PeerConnection.send_pli(input.pc, input.video, layer)

      {:reply, :ok, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:get_layers, _from, state) do
    case state.local_input || state.remote_input do
      nil -> {:reply, :error, state}
      input -> {:reply, {:ok, input.available_layers}, state}
    end
  end

  @impl true
  def handle_call({:connect_input, id, pc}, _from, %{local_input: nil, remote_input: nil} = state) do
    terminate_pending_input(state)
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())

    input = %{
      pc: pc,
      id: id,
      video: nil,
      audio: nil,
      available_layers: nil
    }

    state = %{state | pending_input: input}

    Logger.info("Added new input #{id} (#{inspect(pc)})")
    Process.send_after(self(), {:connect_timeout, pc}, @connect_timeout_ms)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:connect_input, id, _pc}, _from, state) do
    Logger.info("Cannot add input #{id} as there already is one connected.")
    {:reply, :error, state}
  end

  @impl true
  def handle_call({:connect_output, id, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    pending_outputs = MapSet.put(state.pending_outputs, pc)

    Logger.info("Added new output #{inspect(pc)} for input #{inspect(id)}")
    Process.send_after(self(), {:connect_timeout, pc}, @connect_timeout_ms)

    {:reply, :ok, %{state | pending_outputs: pending_outputs}}
  end

  @impl true
  def handle_cast({:set_packet_loss, pc, value}, state) do
    case Map.get(state.outputs, pc) do
      nil ->
        Logger.warning("Tried to set packet loss for non-existing peer connection.")
        {:noreply, state}

      _output ->
        PeerConnection.set_packet_loss(pc, String.to_integer(value))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:connect_timeout, pc}, state) do
    direction =
      cond do
        pc == state.pending_input -> :input
        MapSet.member?(state.pending_outputs, pc) -> :output
        true -> nil
      end

    if direction != nil do
      Logger.warning("""
      Terminating #{direction} #{inspect(pc)} \
      because it didn't connect within #{@connect_timeout_s} seconds \
      """)

      PeerSupervisor.terminate_pc(pc)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, pc, {:connection_state_change, :connected}},
        %{pending_input: %{pc: pc} = input} = state
      ) do
    {audio_track, video_track} = get_tracks(pc, :receiver)

    input = %{
      input
      | video: video_track.id,
        audio: audio_track.id,
        available_layers: video_track.rids
    }

    state = %{state | local_input: input}

    Logger.info("Input #{input.id} (#{inspect(pc)}) has successfully connected")
    Channel.input_added(input.id)

    # ID collisions in the cluster are unlikely and thus will not be checked against
    PubSub.broadcast_from(@pubsub, self(), "inputs", {:input_added, input})

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    case MapSet.member?(state.pending_outputs, pc) do
      true ->
        pending_outpus = MapSet.delete(state.pending_outputs, pc)
        state = %{state | pending_outputs: pending_outpus}

        state =
          case state.local_input || state.remote_input do
            nil ->
              Logger.info("Terminating output #{inspect(pc)} because there is no input")
              PeerSupervisor.terminate_pc(pc)

            input ->
              do_connect_output(pc, input, state)
          end

        {:noreply, state}

      false ->
        # We might have received this message at the same moment we where terminating peer connection
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :failed}}, state) do
    Logger.warning("Peer connection #{inspect(pc)} state changed to `failed`. Terminating")
    PeerSupervisor.terminate_pc(pc)
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, input_pc, {:rtp, input_track, rid, packet}}, state) do
    input = state.local_input || state.remote_input

    state =
      cond do
        input_track == input.audio and rid == nil ->
          PubSub.broadcast(@pubsub, "input:#{input.id}", {:input, input_pc, :audio, nil, packet})
          forward_audio_packet(packet, state)

        input_track == input.video ->
          PubSub.broadcast(@pubsub, "input:#{input.id}", {:input, input_pc, :video, rid, packet})
          forward_video_packet(packet, rid, state)

        true ->
          Logger.warning("Received an RTP packet corresponding to unknown track. Ignoring")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:rtcp, packets}}, state) do
    with {:ok, %{layer: layer}} <- Map.fetch(state.outputs, pc),
         input when not is_nil(input) <- state.local_input || state.remote_input do
      for packet <- packets do
        case packet do
          {_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} ->
            PeerConnection.send_pli(input.pc, input.video, layer)

          _other ->
            :ok
        end
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:input_added, input}, state) do
    Logger.info("New remote input #{input.id}")

    state =
      state
      |> terminate_pending_input()
      |> terminate_local_input()
      |> unsubscribe_remote_input()

    PubSub.subscribe(@pubsub, "input:#{input.id}")

    Logger.info("Subscribed to remote input #{input.id}")

    {:noreply, %{state | remote_input: input}}
  end

  @impl true
  def handle_info({:input_removed, id}, state) do
    case state.remote_input do
      %{id: ^id, pc: pc} = input ->
        Logger.info("Remote input #{input.id} (#{inspect(pc)}) removed")
        state = unsubscribe_remote_input(state)

        for {output_pc, _output} <- state.outputs do
          PeerSupervisor.terminate_pc(output_pc)
        end

        {:noreply, state}

      %{id: id} ->
        Logger.info("Remote input #{id} removed, but we are not subscribed to it. Ignoring.")

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:input, pc, kind, rid, packet}, %{remote_input: %{pc: pc}} = state) do
    state =
      cond do
        kind == :audio and rid == nil ->
          forward_audio_packet(packet, state)

        kind == :video ->
          forward_video_packet(packet, rid, state)

        true ->
          Logger.warning("Received an RTP packet corresponding to unknown remote track. Ignoring")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, reason},
        %{local_input: %{pc: pid} = input} = state
      ) do
    Logger.info(
      "Input #{input.id}: process #{inspect(pid)} exited with reason #{inspect(reason)}"
    )

    for {pc, _} <- state.outputs do
      PeerSupervisor.terminate_pc(pc)
    end

    Channel.input_removed(input.id)
    PubSub.broadcast_from(@pubsub, self(), "inputs", {:input_removed, pid})

    {:noreply, %{state | local_input: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      pid == state.pending_input ->
        Logger.info("""
        Pending input #{state.pending_input.id}: process #{inspect(pid)} \
        exited with reason #{inspect(reason)} \
        """)

        {:noreply, %{state | pending_input: nil}}

      Map.has_key?(state.outputs, pid) ->
        {output, state} = pop_in(state, [:outputs, pid])

        Logger.info("""
        Output process #{inspect(pid)} (input #{output.input_id}) \
        exited with reason #{inspect(reason)} \
        """)

        {:noreply, state}

      MapSet.member?(state.pending_outputs, pid) ->
        pending_outputs = MapSet.delete(state.pending_outputs, pid)
        state = %{state | pending_outputs: pending_outputs}

        Logger.info(
          "Pending output process #{inspect(pid)} exited with reason #{inspect(reason)} "
        )

        {:noreply, state}

      true ->
        Logger.warning("Unknown process #{inspect(pid)} died with reason #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp do_connect_output(pc, input, state) do
    layer = default_layer(input)

    {audio_track, video_track} = get_tracks(pc, :sender)
    munger = Munger.new(90_000)

    output = %{
      audio: audio_track.id,
      video: video_track.id,
      input_id: input.id,
      munger: munger,
      layer: layer,
      pending_layer: layer
    }

    Logger.info("Output #{inspect(pc)} has successfully connected")

    # We don't send a PLI on behalf of the newly connected output.
    # Once the remote end sends a PLI to us, we'll forward it.

    put_in(state, [:outputs, pc], output)
  end

  defp forward_video_packet(packet, rid, state) do
    outputs =
      Map.new(state.outputs, fn
        {pc, %{layer: layer, pending_layer: p_layer} = output} ->
          output =
            if p_layer == rid and p_layer != layer and H264.keyframe?(packet) do
              munger = Munger.update(output.munger)
              %{output | layer: p_layer, munger: munger}
            else
              output
            end

          output =
            if rid == output.layer do
              {packet, munger} = Munger.munge(output.munger, packet)
              PeerConnection.send_rtp(pc, output.video, packet)
              %{output | munger: munger}
            else
              output
            end

          {pc, output}
      end)

    %{state | outputs: outputs}
  end

  defp forward_audio_packet(packet, state) do
    for {pc, output} <- state.outputs do
      PeerConnection.send_rtp(pc, output.audio, packet)
    end

    state
  end

  defp get_tracks(pc, type) do
    transceivers = PeerConnection.get_transceivers(pc)
    audio_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :audio end)
    video_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :video end)

    audio_track = Map.fetch!(audio_transceiver, type).track
    video_track = Map.fetch!(video_transceiver, type).track

    {audio_track, video_track}
  end

  defp default_layer(%{available_layers: nil}), do: nil
  defp default_layer(%{available_layers: [first | _]}), do: first

  defp terminate_pending_input(%{pending_input: nil} = state), do: state

  defp terminate_pending_input(%{pending_input: %{pc: pc, id: id}} = state) when is_pid(pc) do
    Logger.info("Terminating pending local input: #{id}")
    :ok = PeerSupervisor.terminate_pc(pc)
    %{state | pending_input: nil}
  end

  defp terminate_local_input(%{local_input: nil} = state), do: state

  defp terminate_local_input(%{local_input: %{pc: pc, id: id}} = state) when is_pid(pc) do
    Logger.info("Terminating local input: #{id}")
    :ok = PeerSupervisor.terminate_pc(pc)
    PubSub.broadcast_from(@pubsub, self(), "inputs", {:input_removed, pc})
    %{state | local_input: nil}
  end

  defp unsubscribe_remote_input(%{remote_input: nil} = state), do: state

  defp unsubscribe_remote_input(%{remote_input: %{id: id}} = state) do
    Logger.info("Unsubscribing from remote input: #{id}")
    PubSub.unsubscribe(@pubsub, "input:#{id}")
    %{state | remote_input: nil}
  end
end
