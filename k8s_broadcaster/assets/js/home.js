import { Socket, Presence } from "phoenix";

import { WHEPClient } from "./whep-client.js";

async function connectSignaling(view) {
  view.channel = view.socket.channel("k8s_broadcaster:signaling");

  const presence = new Presence(view.channel);
  presence.onSync(() => (viewercount.innerText = presence.list().length));

  view.channel.on("input_added", ({ id: id }) => {
    console.log("New input:", id);
    view.inputId = id;
    connectInput(view);
  });

  view.channel.on("input_removed", ({ id: id }) => {
    console.log("Input removed:", id);
    removeInput(view);
  });

  view.channel
    .join()
    .receive("ok", () => {
      console.log("Joined signaling channel successfully");
      view.statusMessage.innerText =
        "Connected. Waiting for the stream to begin...";
      view.statusMessage.classList.remove("hidden");
    })
    .receive("error", (resp) => {
      console.error("Unable to join signaling channel", resp);
      view.statusMessage.innerText =
        "Unable to join the stream, try again in a few minutes";
      view.statusMessage.classList.remove("hidden");
    });
}

async function connectInput(view) {
  let whepEndpoint;
  if (view.url) {
    whepEndpoint = view.url + "api/whep?inputId=" + view.inputId;
  } else {
    whepEndpoint = view.whepEndpointBase + "?inputId=" + view.inputId;
  }

  console.log("Trying to connect to: ", whepEndpoint);

  if (view.inputId) {
    removeInput(view);
  }

  const pcConfigUrl = (view.url || window.location.origin) + "/api/pc-config";
  const response = await fetch(pcConfigUrl, {
    method: "GET",
    cache: "no-cache",
  });
  const pcConfig = await response.json();
  console.log("Fetched PC config from server: ", pcConfig);

  view.whepClient = new WHEPClient(whepEndpoint, pcConfig);
  view.whepClient.id = view.inputId;

  view.whepClient.onstream = (stream) => {
    console.log(`[${view.inputId}]: Received new stream`);
    view.videoPlayer.srcObject = stream;
    view.statusMessage.classList.add("hidden");
  };

  view.whepClient.onconnected = () => {
    view.packetLossRange.onchange = () => {
      view.packetLossRangeOutput.value = view.packetLossRange.value;
      channel.push("packet_loss", {
        resourceId: view.whepClient.resourceId,
        value: view.packetLossRange.value,
      });
    };

    view.rtxCheckbox.onchange = () => {
      connectInput();
    };

    view.videoQuality.onchange = () => setDefaultLayer(view.videoQuality.value);

    view.whepClient.changeLayer(view.defaultLayer);

    if (view.whepClient.pc.connectionState === "connected") {
      view.stats.startTime = new Date();
      view.stats.intervalId = setInterval(async function () {
        if (!view.whepClient.pc) {
          clearInterval(view.stats.intervalId);
          view.stats.intervalId = undefined;
          return;
        }

        view.stats.time.innerText = toHHMMSS(new Date() - view.stats.startTime);

        let bitrate;

        (await view.whepClient.pc.getStats(null)).forEach((report) => {
          if (report.type === "inbound-rtp" && report.kind === "video") {
            if (!view.stats.lastVideoReport) {
              bitrate = (report.bytesReceived * 8) / 1000;
            } else {
              const timeDiff =
                (report.timestamp - view.stats.lastVideoReport.timestamp) /
                1000;
              if (timeDiff == 0) {
                // this should never happen as we are getting stats every second
                bitrate = 0;
              } else {
                bitrate =
                  ((report.bytesReceived -
                    view.stats.lastVideoReport.bytesReceived) *
                    8) /
                  timeDiff;
              }
            }

            view.stats.videoBitrate.innerText = (bitrate / 1000).toFixed();
            view.stats.frameWidth.innerText = report.frameWidth;
            view.stats.frameHeight.innerText = report.frameHeight;
            view.stats.fps.innerText = report.framesPerSecond;
            view.stats.keyframesDecoded.innerText = report.keyFramesDecoded;
            view.stats.pliCount.innerText = report.pliCount;
            view.stats.avgJitterBufferDelay.innerText =
              (report.jitterBufferDelay * 1000) /
              report.jitterBufferEmittedCount;
            view.stats.freezeCount.innerText = report.freezeCount;
            view.stats.freezeDuration.innerText = report.totalFreezesDuration;
            view.stats.lastVideoReport = report;
          } else if (report.type === "inbound-rtp" && report.kind === "audio") {
            if (!stats.lastAudioReport) {
              bitrate = report.bytesReceived;
            } else {
              const timeDiff =
                (report.timestamp - view.stats.lastAudioReport.timestamp) /
                1000;
              if (timeDiff == 0) {
                // this should never happen as we are getting stats every second
                bitrate = 0;
              } else {
                bitrate =
                  ((report.bytesReceived -
                    view.stats.lastAudioReport.bytesReceived) *
                    8) /
                  timeDiff;
              }
            }

            view.stats.audioBitrate.innerText = (bitrate / 1000).toFixed();
            view.stats.lastAudioReport = report;
          }
        });

        let packetsLost = 0;
        let packetsReceived = 0;
        // calculate packet loss
        if (view.stats.lastAudioReport) {
          packetsLost += view.stats.lastAudioReport.packetsLost;
          packetsReceived += view.stats.lastAudioReport.packetsReceived;
        }

        if (view.stats.lastVideoReport) {
          packetsLost += view.stats.lastVideoReport.packetsLost;
          packetsReceived += view.stats.lastVideoReport.packetsReceived;
        }

        if (packetsReceived == 0) {
          view.stats.packetLoss.innerText = 0;
        } else {
          view.stats.packetLoss.innerText = (
            (packetsLost / packetsReceived) *
            100
          ).toFixed(2);
        }
      }, 1000);
    } else if (view.whepClient.pc.connectionState === "failed") {
    }
  };

  view.whepClient.connect(view.rtxCheckbox.checked);
}

async function removeInput(view) {
  if (view.whepClient) {
    console.log("Disconnecting WHEP client.");
    view.whepClient.disconnect();
    view.whepClient = undefined;
    view.videoPlayer.srcObject = null;
  }

  view.statusMessage.innerText =
    "Connected. Waiting for the stream to begin...";
  view.statusMessage.classList.remove("hidden");

  clearInterval(view.stats.intervalId);
  view.stats.lastAudioReport = null;
  view.stats.lastVideoReport = null;
  view.stats.time.innerText = 0;
  view.stats.audioBitrate.innerText = 0;
  view.stats.videoBitrate.innerText = 0;
  view.stats.frameWidth.innerText = 0;
  view.stats.frameHeight.innerText = 0;
  view.stats.fps.innerText = 0;
  view.stats.keyframesDecoded.innerText = 0;
  view.stats.pliCount.innerText = 0;
  view.stats.packetLoss.innerText = 0;
  view.stats.avgJitterBufferDelay.innerText = 0;
  view.stats.freezeCount.innerText = 0;
  view.stats.freezeDuration.innerText = 0;
}

async function setDefaultLayer(view, layer) {
  if (view.defaultLayer !== layer) {
    view.defaultLayer = layer;
    view.whepClient.changeLayer(layer);
  }
}

function toHHMMSS(milliseconds) {
  // Calculate hours
  let hours = Math.floor(milliseconds / (1000 * 60 * 60));
  // Calculate minutes, subtracting the hours part
  let minutes = Math.floor((milliseconds % (1000 * 60 * 60)) / (1000 * 60));
  // Calculate seconds, subtracting the hours and minutes parts
  let seconds = Math.floor((milliseconds % (1000 * 60)) / 1000);

  // Formatting each unit to always have at least two digits
  hours = hours < 10 ? "0" + hours : hours;
  minutes = minutes < 10 ? "0" + minutes : minutes;
  seconds = seconds < 10 ? "0" + seconds : seconds;

  return hours + ":" + minutes + ":" + seconds;
}

function resetButtons(view) {
  view.button1.classList.remove("border-green-500");
  view.button2.classList.remove("border-green-500");
  view.button3.classList.remove("border-green-500");
  view.buttonAuto.classList.remove("border-green-500");
}

function colorButton(button) {
  button.classList.toggle("border-green-500");
}

function buttonOnClick(view, button) {
  view.url = button.value;
  resetButtons(view);
  colorButton(button);
  connectInput(view);
}

export const Home = {
  mounted() {
    // read html elements
    const view = this;
    view.viewercount = document.getElementById("viewercount");
    view.videoQuality = document.getElementById("video-quality");
    view.rtxCheckbox = document.getElementById("rtx-checkbox");
    view.videoPlayer = document.getElementById("videoplayer");
    view.statusMessage = document.getElementById("status-message");
    view.packetLossRange = document.getElementById("packet-loss-range");
    view.packetLossRangeOutput = document.getElementById(
      "packet-loss-range-output"
    );
    view.button1 = document.getElementById("button-1");
    view.button2 = document.getElementById("button-2");
    view.button3 = document.getElementById("button-3");
    view.buttonAuto = document.getElementById("button-auto");

    view.stats = {
      time: document.getElementById("time"),
      audioBitrate: document.getElementById("audio-bitrate"),
      videoBitrate: document.getElementById("video-bitrate"),
      frameWidth: document.getElementById("frame-width"),
      frameHeight: document.getElementById("frame-height"),
      fps: document.getElementById("fps"),
      keyframesDecoded: document.getElementById("keyframes-decoded"),
      pliCount: document.getElementById("pli-count"),
      packetLoss: document.getElementById("packet-loss"),
      avgJitterBufferDelay: document.getElementById("avg-jitter-buffer-delay"),
      freezeCount: document.getElementById("freeze-count"),
      freezeDuration: document.getElementById("freeze-duration"),
    };

    // declare custom fields
    view.whepEndpointBase = `${window.location.origin}/api/whep`;
    view.defaultLayer = "h";
    view.url = undefined;
    view.inputId = undefined;
    view.channel = undefined;
    view.whepClient = undefined;

    // connect to the signaling
    view.socket = new Socket("/socket", {
      params: { token: window.userToken },
    });
    view.socket.connect();

    connectSignaling(view);

    view.button1.onclick = (ev) => buttonOnClick(view, ev.srcElement);
    view.button2.onclick = (ev) => buttonOnClick(view, ev.srcElement);
    view.button3.onclick = (ev) => buttonOnClick(view, ev.srcElement);
    view.buttonAuto.onclick = (ev) => buttonOnClick(view, ev.srcElement);
  },
};
