import { Socket, Presence } from "phoenix";

import { WHEPClient } from "./whep_client.js";
import { TimeSeries } from "./time_series.js";

import Chart from "chart.js/auto";
import { Globe } from "./globe.js";

async function connectSignaling(view) {
  view.channel = view.socket.channel("k8s_broadcaster:signaling");

  const presence = new Presence(view.channel);
  presence.onSync(() => (viewercount.innerText = presence.list().length));

  view.channel.on("input_added", ({ id: id, region: region }) => {
    console.log("New input:", id);
    view.inputId = id;
    view.globe.setStreamerRegion(region);
    connectInput(view);
  });

  view.channel.on("input_removed", ({ id: id }) => {
    console.log("Input removed:", id);
    view.globe.removeArcs();
    removeInput(view);
  });

  view.channel
    .join()
    .receive("ok", ({ labels: labels }) => {
      console.log("Joined signaling channel successfully");
      view.globe.addLabels(labels);
      // view.statusMessage.innerText =
      //   "Connected. Waiting for the stream to begin...";
      // view.statusMessage.classList.remove("hidden");
    })
    .receive("error", (resp) => {
      console.error("Unable to join signaling channel", resp);
      // view.statusMessage.innerText =
      //   "Unable to join the stream, try again in a few minutes";
      // view.statusMessage.classList.remove("hidden");
    });
}

async function connectInput(view) {
  let whepEndpoint;
  if (view.url) {
    whepEndpoint = view.url + "api/whep";
  } else {
    whepEndpoint = view.whepEndpointBase;
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
    // view.statusMessage.classList.add("hidden");
  };

  view.whepClient.onconnected = async () => {
    const regionUrl = (view.url || window.location.origin) + "/api/region?resourceId=" + view.whepClient.resourceId;
    const response = await fetch(regionUrl, {
      method: "GET",
      cache: "no-cache"
    });

    if (response.status === 200) {
      const region = await response.text();
      view.globe.setConnectedRegion(region);
    }

    view.packetLossRange.onchange = () => {
      view.packetLossRangeOutput.value = view.packetLossRange.value;
      view.channel.push("packet_loss", {
        resourceId: view.whepClient.resourceId,
        value: view.packetLossRange.value,
      });
    };

    view.rtxCheckbox.onchange = () => {
      connectInput(view);
    };

    view.videoQuality.onchange = () => setDefaultLayer(view.videoQuality.value);

    view.whepClient.changeLayer(view.defaultLayer);

    if (view.whepClient.pc.connectionState === "connected") {
      view.stats.startTime = new Date();
      view.stats.intervalId = setInterval(readPCStats, 1000, view);
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

  // view.statusMessage.innerText =
  //   "Connected. Waiting for the stream to begin...";
  // view.statusMessage.classList.remove("hidden");

  clearInterval(view.stats.intervalId);
  view.stats.lastAudioReport = null;
  view.stats.lastVideoReport = null;
  view.stats.duration.innerText = 0;
  view.stats.audioBitrate.innerText = 0;
  view.stats.videoBitrate.innerText = 0;
  view.stats.frameWidth.innerText = 0;
  view.stats.frameHeight.innerText = 0;
  view.stats.fps.innerText = 0;
  view.stats.keyframesDecoded.innerText = 0;
  view.stats.pliCount.innerText = 0;
  view.stats.packetLoss.innerText = 0;
  view.stats.nackCount.innerText = 0;
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

async function readPCStats(view) {
  if (!view.whepClient.pc) {
    clearInterval(view.stats.intervalId);
    view.stats.intervalId = undefined;
    return;
  }

  view.stats.duration.innerText = toHHMMSS(new Date() - view.stats.startTime);

  (await view.whepClient.pc.getStats(null)).forEach((report) => {
    if (report.type === "candidate-pair" && report.nominated === true) {
      processCandidatePairReport(view, report);
    } else if (report.type === "inbound-rtp" && report.kind === "video") {
      processVideoReport(view, report);
    } else if (report.type === "inbound-rtp" && report.kind === "audio") {
      processAudioReport(view, report);
    }
  });

  updatePacketLoss(view);
}

function processCandidatePairReport(view, report) {
  const timestamp = toXLabel(new Date(report.timestamp));
  view.stats.rtt.innerText = report.currentRoundTripTime * 1000;
  view.stats.rttTS.push(timestamp, report.currentRoundTripTime * 1000);
  view.rttChart.update();

  let packetsReceived = 0;
  if (view.stats.lastCandidatePairReport) {
    const timeDiff =
      (report.timestamp - view.stats.lastCandidatePairReport.timestamp) / 1000;
    if (timeDiff == 0) {
      packetsReceived = 0;
    } else {
      packetsReceived =
        (report.packetsReceived -
          view.stats.lastCandidatePairReport.packetsReceived) /
        timeDiff;
    }
  }

  packetsReceived = packetsReceived.toFixed();

  view.stats.packetsReceived.innerText = packetsReceived;
  view.stats.packetsReceivedTS.push(timestamp, packetsReceived);
  view.packetsReceivedChart.update();

  view.stats.lastCandidatePairReport = report;
}

function processVideoReport(view, report) {
  const timestamp = toXLabel(new Date(report.timestamp));
  let bitrate = 0;
  let avgJitterBufferDelay = 0;

  if (!view.stats.lastVideoReport) {
    bitrate = (report.bytesReceived * 8) / 1000;

    if (report.jitterBufferEmittedCount != 0) {
      avgJitterBufferDelay =
        report.jitterBufferDelay / report.jitterBufferEmittedCount;
    }
  } else {
    const timeDiff =
      (report.timestamp - view.stats.lastVideoReport.timestamp) / 1000;
    if (timeDiff != 0) {
      bitrate =
        ((report.bytesReceived - view.stats.lastVideoReport.bytesReceived) *
          8) /
        timeDiff;

      const jitterBufferDelay =
        (report.jitterBufferDelay -
          view.stats.lastVideoReport.jitterBufferDelay) *
        1000;
      const jitterBufferEmittedCount =
        report.jitterBufferEmittedCount -
        view.stats.lastVideoReport.jitterBufferEmittedCount;

      if (jitterBufferEmittedCount != 0) {
        avgJitterBufferDelay =
          jitterBufferDelay / jitterBufferEmittedCount / timeDiff;
      }
    }
  }

  const btr = (bitrate / 1000).toFixed();

  view.stats.videoBitrate.innerText = btr;
  view.stats.frameWidth.innerText = report.frameWidth;
  view.stats.frameHeight.innerText = report.frameHeight;
  view.stats.fps.innerText = report.framesPerSecond || 0;
  view.stats.keyframesDecoded.innerText = report.keyFramesDecoded;
  view.stats.pliCount.innerText = report.pliCount;
  view.stats.avgJitterBufferDelay.innerText = avgJitterBufferDelay.toFixed(2);
  view.stats.freezeCount.innerText = report.freezeCount;
  view.stats.freezeDuration.innerText = report.totalFreezesDuration;
  // nacks seem to be present only for video?
  view.stats.nackCount = report.nackCount;

  // update last and previous reports
  if (view.stats.lastVideoReport) {
    view.stats.prevVideoReport = view.stats.lastVideoReport;
  } else {
    view.stats.prevVideoReport = report;
  }

  view.stats.lastVideoReport = report;

  // charts
  view.stats.videoBitrateTS.push(timestamp, btr);
  view.stats.fpsTS.push(timestamp, report.framesPerSecond || 0);
  view.stats.keyframesDecodedTS.push(timestamp, report.keyFramesDecoded);
  view.stats.pliCountTS.push(timestamp, report.pliCount);
  view.stats.avgJitterTS.push(timestamp, avgJitterBufferDelay.toFixed(2));
  view.stats.freezeCountTS.push(timestamp, report.freezeCount);
  view.stats.freezeDurationTS.push(timestamp, report.totalFreezesDuration);
  view.stats.nackCountTS.push(timestamp, report.nackCount);
  view.videoChart.update();
  view.fpsChart.update();
  view.keyframesDecodedChart.update();
  view.pliCountChart.update();
  view.avgJitterChart.update();
  view.freezeCountChart.update();
  view.freezeDurationChart.update();
  view.nackCountChart.update();
}

function processAudioReport(view, report) {
  const timestamp = toXLabel(new Date(report.timestamp));
  let bitrate;
  if (!view.stats.lastAudioReport) {
    bitrate = report.bytesReceived;
  } else {
    const timeDiff =
      (report.timestamp - view.stats.lastAudioReport.timestamp) / 1000;
    if (timeDiff == 0) {
      // this should never happen as we are getting stats every second
      bitrate = 0;
    } else {
      bitrate =
        ((report.bytesReceived - view.stats.lastAudioReport.bytesReceived) *
          8) /
        timeDiff;
    }
  }

  const btr = (bitrate / 1000).toFixed();
  view.stats.audioBitrate.innerText = btr;

  if (view.stats.lastAudioReport) {
    view.stats.prevAudioReport = view.stats.lastAudioReport;
  } else {
    view.stats.prevAudioReport = report;
  }

  view.stats.lastAudioReport = report;

  view.stats.audioBitrateTS.push(timestamp, btr);
  view.audioChart.update();
}

function updatePacketLoss(view) {
  let timeDiff = 0;

  let packetsLost = 0;
  let packetsReceived = 0;
  // calculate packet loss
  if (view.stats.lastAudioReport && view.stats.prevAudioReport) {
    packetsLost +=
      view.stats.lastAudioReport.packetsLost -
      view.stats.prevAudioReport.packetsLost;
    packetsReceived +=
      view.stats.lastAudioReport.packetsReceived -
      view.stats.prevAudioReport.packetsReceived;

    timeDiff =
      (view.stats.lastAudioReport.timestamp -
        view.stats.prevAudioReport.timestamp) /
      1000;
  }

  if (view.stats.lastVideoReport && view.stats.prevVideoReport) {
    packetsLost +=
      view.stats.lastVideoReport.packetsLost -
      view.stats.prevVideoReport.packetsLost;
    packetsReceived +=
      view.stats.lastVideoReport.packetsReceived -
      view.stats.prevVideoReport.packetsReceived;

    timeDiff =
      (view.stats.lastVideoReport.timestamp -
        view.stats.prevVideoReport.timestamp) /
      1000;
  }

  let packetLoss;
  if (packetsReceived == 0 || timeDiff == 0) {
    packetLoss = 0;
  } else {
    packetLoss = ((packetsLost / packetsReceived) * 100) / timeDiff;
    packetLoss = packetLoss.toFixed(2);
  }

  const timestamp = toXLabel(
    new Date(
      view.stats.lastAudioReport.timestamp ||
      view.stats.lastVideoReport.timestamp
    )
  );
  view.stats.packetLoss.innerText = packetLoss;

  view.stats.packetLossTS.push(timestamp, packetLoss);
  view.packetLossChart.update();
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

function toXLabel(time) {
  return time.getHours() + ":" + time.getMinutes() + ":" + time.getSeconds();
}

function createChart(ctx, name, ts) {
  return new Chart(ctx, {
    type: "line",
    data: {
      labels: ts.x,
      datasets: [
        {
          data: ts.y,
          borderWidth: 1,
          pointRadius: 0,
          borderColor: "#675AF1",
        },
      ],
    },
    options: {
      plugins: {
        title: {
          display: true,
          text: name,
        },
        legend: {
          display: false,
        },
      },

      animation: {
        duration: 0,
      },
      scales: {
        y: {
          beginAtZero: false,
          min: 0,
        },
        x: {
          ticks: {
            maxRotation: 0,
          },
        },
      },
    },
  });
}

export const Home = {
  mounted() {
    // read html elements
    const view = this;
    view.viewercount = document.getElementById("viewercount");
    view.videoQuality = document.getElementById("video-quality");
    view.rtxCheckbox = document.getElementById("rtx-checkbox");
    view.videoPlayer = document.getElementById("videoplayer");
    // view.statusMessage = document.getElementById("status-message");
    view.packetLossRange = document.getElementById("packet-loss-range");
    view.packetLossRangeOutput = document.getElementById(
      "packet-loss-range-output"
    );
    view.button1 = document.getElementById("button-1");
    view.button2 = document.getElementById("button-2");
    view.button3 = document.getElementById("button-3");
    view.buttonAuto = document.getElementById("button-auto");

    view.stats = {
      duration: document.getElementById("duration"),
      rtt: document.getElementById("rtt"),
      audioBitrate: document.getElementById("audio-bitrate"),
      videoBitrate: document.getElementById("video-bitrate"),
      packetsReceived: document.getElementById("packets-received"),
      frameWidth: document.getElementById("frame-width"),
      frameHeight: document.getElementById("frame-height"),
      fps: document.getElementById("fps"),
      keyframesDecoded: document.getElementById("keyframes-decoded"),
      pliCount: document.getElementById("pli-count"),
      packetLoss: document.getElementById("packet-loss"),
      nackCount: document.getElementById("nack-count"),
      avgJitterBufferDelay: document.getElementById("avg-jitter-buffer-delay"),
      freezeCount: document.getElementById("freeze-count"),
      freezeDuration: document.getElementById("freeze-duration"),

      // time series
      rttTS: new TimeSeries().populateLastMinute(),
      audioBitrateTS: new TimeSeries().populateLastMinute(),
      videoBitrateTS: new TimeSeries().populateLastMinute(),
      packetsReceivedTS: new TimeSeries().populateLastMinute(),
      fpsTS: new TimeSeries().populateLastMinute(),
      keyframesDecodedTS: new TimeSeries().populateLastMinute(),
      pliCountTS: new TimeSeries().populateLastMinute(),
      packetLossTS: new TimeSeries().populateLastMinute(),
      nackCountTS: new TimeSeries().populateLastMinute(),
      avgJitterTS: new TimeSeries().populateLastMinute(),
      freezeCountTS: new TimeSeries().populateLastMinute(),
      freezeDurationTS: new TimeSeries().populateLastMinute(),
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

    view.rttChart = createChart(
      document.getElementById("rtt-chart"),
      "rtt (ms)",
      view.stats.rttTS
    );
    view.packetsReceivedChart = createChart(
      document.getElementById("packetsReceived-chart"),
      "packetsReceived/s",
      view.stats.packetsReceivedTS
    );
    view.audioChart = createChart(
      document.getElementById("audio-chart"),
      "audioBitrate (kbps)",
      view.stats.audioBitrateTS
    );
    view.videoChart = createChart(
      document.getElementById("video-chart"),
      "videoBitrate (kbps)",
      view.stats.videoBitrateTS
    );
    view.fpsChart = createChart(
      document.getElementById("fps-chart"),
      "FPS",
      view.stats.fpsTS
    );
    view.keyframesDecodedChart = createChart(
      document.getElementById("keyframesDecoded-chart"),
      "keyframesDecoded",
      view.stats.keyframesDecodedTS
    );
    view.pliCountChart = createChart(
      document.getElementById("pliCount-chart"),
      "pliCount",
      view.stats.pliCountTS
    );
    view.packetLossChart = createChart(
      document.getElementById("packetLoss-chart"),
      "packetLoss (%)",
      view.stats.packetLossTS
    );
    view.nackCountChart = createChart(
      document.getElementById("nackCount-chart"),
      "nackCount",
      view.stats.nackCountTS
    );
    view.avgJitterChart = createChart(
      document.getElementById("avgJitter-chart"),
      "avgJitterBufferDelay (ms)",
      view.stats.avgJitterTS
    );
    view.freezeCountChart = createChart(
      document.getElementById("freezeCount-chart"),
      "freezeCount",
      view.stats.freezeCountTS
    );
    view.freezeDurationChart = createChart(
      document.getElementById("freezeDuration-chart"),
      "freezeDuration",
      view.stats.freezeDurationTS
    );

    view.globe = new Globe("cluster-view");
    view.globe.animate();

    document.getElementById("localize").onclick = () => {
      navigator.geolocation.getCurrentPosition((position) => {
        label = { text: "YOU", type: "client", lat: position.coords.latitude, lng: position.coords.longitude };
        view.globe.addLabels([label]);
      });
    };

    document.getElementById("rotate").onclick = () => {
      console.log(view.globe.controls.autoRotate);
      view.globe.controls.autoRotate = !view.globe.controls.autoRotate;
    };




    console.log("Started globe animation");
  },
};
