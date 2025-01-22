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
    view.streamSource.innerText = region.toUpperCase();
    connectInput(view);
  });

  view.channel.on("input_removed", ({ id: id }) => {
    console.log("Input removed:", id);
    view.globe.removeArcs();
    view.globe.clearStreamerRegion();
    view.streamSource.innerText = "WAITING";
    view.connectedTo.innerText = "WAITING";
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
    whepEndpoint = view.url;
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
    const regionUrl =
      (view.url || window.location.origin) +
      "/api/region?resourceId=" +
      view.whepClient.resourceId;
    const response = await fetch(regionUrl, {
      method: "GET",
      cache: "no-cache",
    });

    if (response.status === 200) {
      const region = await response.text();
      view.globe.setConnectedRegion(region);
      view.connectedTo.innerText = region.toUpperCase();
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

    view.videoQuality.onchange = () =>
      setDefaultLayer(view, view.videoQuality.value);

    view.whepClient.changeLayer(view.defaultLayer);

    if (view.whepClient.pc.connectionState === "connected") {
      view.recordBtn.onclick = () => startRecording(view);
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
  view.stats.rtt.innerText = 0;
  view.stats.rttShort.innerText = 0;
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
  view.stats.avgJitterBufferDelayShort.innerText = 0;
  view.stats.freezeCount.innerText = 0;
  view.stats.freezeDuration.innerText = 0;
  view.stats.freezeDurationShort.innerText = 0;
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
  view.stats.rttShort.innerText = report.currentRoundTripTime * 1000;
  view.stats.rttTS.push(timestamp, report.currentRoundTripTime * 1000);
  record(view.recorder.rttTS, timestamp, report.currentRoundTripTime * 1000);
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
  record(view.recorder.packetsReceivedTS, timestamp, packetsReceived);

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
  view.stats.avgJitterBufferDelayShort.innerText =
    avgJitterBufferDelay.toFixed(2);
  view.stats.freezeCount.innerText = report.freezeCount;
  view.stats.freezeDuration.innerText = report.totalFreezesDuration;
  view.stats.freezeDurationShort.innerText = report.totalFreezesDuration;
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

  record(view.recorder.videoBitrateTS, timestamp, btr);
  record(view.recorder.fpsTS, timestamp, report.framesPerSecond || 0);
  record(view.recorder.keyframesDecodedTS, timestamp, report.keyFramesDecoded);
  record(view.recorder.pliCountTS, timestamp, report.pliCount);
  record(view.recorder.avgJitterTS, timestamp, avgJitterBufferDelay.toFixed(2));
  record(view.recorder.freezeCountTS, timestamp, report.freezeCount);
  record(
    view.recorder.freezeDurationTS,
    timestamp,
    report.totalFreezesDuration
  );
  record(view.recorder.nackCountTS, timestamp, report.nackCount);

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
  record(view.recorder.audioBitrateTS, timestamp, btr);
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
  record(view.recorder.packetLossTS, timestamp, packetLoss);
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

function record(ts, timestamp, data) {
  if (ts) {
    ts.push(timestamp, data);
  }
}

function buttonOnClick(view, button) {
  view.url = button.value;
  view.globe.setConnectedRegion(null);
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

function createCompChart(ctx, name, ts1, ts2) {
  return new Chart(ctx, {
    type: "line",
    data: {
      labels: ts1.x,
      datasets: [
        {
          data: ts1.y,
          borderWidth: 1,
          pointRadius: 0,
          borderColor: "#675AF1",
        },
        {
          data: ts2.y,
          borderWidth: 1,
          pointRadius: 0,
          borderColor: "#3AC2BE",
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

function destroyChart(chart) {
  if (chart) {
    chart.destroy();
  }
}

// recording related functions
function startRecording(view) {
  // one hour assuming getStats is called every second
  maxPoints = 3600;
  view.recorder = {
    startTime: new Date(),
    rttTS: new TimeSeries(maxPoints),
    audioBitrateTS: new TimeSeries(maxPoints),
    videoBitrateTS: new TimeSeries(maxPoints),
    packetsReceivedTS: new TimeSeries(maxPoints),
    fpsTS: new TimeSeries(maxPoints),
    keyframesDecodedTS: new TimeSeries(maxPoints),
    pliCountTS: new TimeSeries(maxPoints),
    packetLossTS: new TimeSeries(maxPoints),
    nackCountTS: new TimeSeries(maxPoints),
    avgJitterTS: new TimeSeries(maxPoints),
    freezeCountTS: new TimeSeries(maxPoints),
    freezeDurationTS: new TimeSeries(maxPoints),
  };

  view.recordBtn.onclick = () => stopRecording(view);
  view.recordBtn.innerText = "Stop recording metrics";
}

function stopRecording(view) {
  const rows = zip(
    view.recorder.rttTS.y,
    view.recorder.audioBitrateTS.y,
    view.recorder.videoBitrateTS.y,
    view.recorder.packetsReceivedTS.y,
    view.recorder.fpsTS.y,
    view.recorder.keyframesDecodedTS.y,
    view.recorder.pliCountTS.y,
    view.recorder.packetLossTS.y,
    view.recorder.nackCountTS.y,
    view.recorder.avgJitterTS.y,
    view.recorder.freezeCountTS.y,
    view.recorder.freezeDurationTS.y
  );

  let csvContent =
    "rtt,audioBitrate,videoBitrate,packetsReceived,fps,keyframesDecoded,pliCount,packetLoss,nackCount,avgJitter,freezeCount,freezeDuration\n" +
    rows.map((r) => r.join(",")).join("\n");

  var file = new Blob([csvContent], { type: "text" });

  const filename =
    view.streamSource.innerText +
    "_" +
    view.connectedTo.innerText +
    "_" +
    view.recorder.startTime.toISOString() +
    ".csv";

  var a = document.createElement("a");
  var url = URL.createObjectURL(file);
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  setTimeout(function () {
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  }, 0);

  view.recorder = {};

  view.recordBtn.onclick = () => startRecording(view);
  view.recordBtn.innerText = "Record metrics";
}

function zip(...arrays) {
  return arrays[0].map(function (_e, i) {
    return arrays.map(function (a) {
      return a[i];
    });
  });
}

function parseCsv(content) {
  const rowsTxt = content.split("\n");
  const rows = rowsTxt.map(function (r) {
    return r.split(",");
  });
  return zip(...rows.slice(1));
}

function compare(view) {
  const f1 = view.file1.files[0];
  const f2 = view.file2.files[0];

  if (!f1 || !f2) return;

  const reader1 = new FileReader();
  const reader2 = new FileReader();

  var columns1;
  var columns2;

  reader1.onload = (ev) => (columns1 = parseCsv(ev.target.result));
  reader2.onload = (ev) => {
    columns2 = parseCsv(ev.target.result);
    displayComparision(view, columns1, columns2);
  };

  reader1.readAsText(f1);
  reader2.readAsText(f2);
}

function displayComparision(view, columns1, columns2) {
  let ts1 = columns1.map(function (c) {
    return c.reduce(function (ts, el, idx) {
      ts.push(idx, el);
      return ts;
    }, new TimeSeries(3600));
  });

  let ts2 = columns2.map(function (c) {
    return c.reduce(function (ts, el, idx) {
      ts.push(idx, el);
      return ts;
    }, new TimeSeries(3600));
  });

  if (ts2[0].x.length > ts1[0].x.length) {
    // switch time series
    // we always draw t1.x.length number of points
    const tmp = ts1;
    ts1 = ts2;
    ts2 = tmp;
  }

  destroyChart(view.crttChart);
  destroyChart(view.ccaudioChart);
  destroyChart(view.cvideoChart);
  destroyChart(view.cpacketsReceivedChart);
  destroyChart(view.cfpsChart);
  destroyChart(view.ckeyframesDecodedChart);
  destroyChart(view.cpliCountChart);
  destroyChart(view.cpacketLossChart);
  destroyChart(view.cnackCountChart);
  destroyChart(view.cavgJitterChart);
  destroyChart(view.cfreezeCountChart);
  destroyChart(view.cfreezeDurationChart);

  view.crttChart = createCompChart(
    document.getElementById("c-rtt-chart"),
    "RTT (ms)",
    ts1[0],
    ts2[0]
  );
  view.ccaudioChart = createCompChart(
    document.getElementById("c-audio-chart"),
    "audioBitrate (kbps)",
    ts1[1],
    ts2[1]
  );
  view.cvideoChart = createCompChart(
    document.getElementById("c-video-chart"),
    "videoBitrate (kbps)",
    ts1[2],
    ts2[2]
  );
  view.cpacketsReceivedChart = createCompChart(
    document.getElementById("c-packetsReceived-chart"),
    "packetsReceived/s",
    ts1[3],
    ts2[3]
  );
  view.cfpsChart = createCompChart(
    document.getElementById("c-fps-chart"),
    "FPS",
    ts1[4],
    ts2[4]
  );
  view.ckeyframesDecodedChart = createCompChart(
    document.getElementById("c-keyframesDecoded-chart"),
    "keyframesDecoded",
    ts1[5],
    ts2[5]
  );
  view.cpliCountChart = createCompChart(
    document.getElementById("c-pliCount-chart"),
    "pliCount",
    ts1[6],
    ts2[6]
  );
  view.cpacketLossChart = createCompChart(
    document.getElementById("c-packetLoss-chart"),
    "packetLoss (%)",
    ts1[7],
    ts2[7]
  );
  view.cnackCountChart = createCompChart(
    document.getElementById("c-nackCount-chart"),
    "nackCount",
    ts1[8],
    ts2[8]
  );
  view.cavgJitterChart = createCompChart(
    document.getElementById("c-avgJitter-chart"),
    "avgJitterBufferDelay (ms)",
    ts1[9],
    ts2[9]
  );
  view.cfreezeCountChart = createCompChart(
    document.getElementById("c-freezeCount-chart"),
    "freezeCount",
    ts1[10],
    ts2[10]
  );
  view.cfreezeDurationChart = createCompChart(
    document.getElementById("c-freezeDuration-chart"),
    "freezeDuration",
    ts1[11],
    ts2[11]
  );
}

export const Home = {
  mounted() {
    // read html elements
    const view = this;
    view.streamSource = document.getElementById("stream-source");
    view.connectedTo = document.getElementById("connected-to");
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
    view.recordBtn = document.getElementById("record-btn");
    view.statisticsTab = document.getElementById("statistics-tab");
    view.compareTab = document.getElementById("compare-tab");
    view.compareStats = document.getElementById("compare-stats");
    view.videoplayerStats = document.getElementById("videoplayer-stats");
    view.file1 = document.getElementById("file-1");
    view.file2 = document.getElementById("file-2");
    view.compareBtn = document.getElementById("compare-btn");

    view.statisticsTab.onclick = () => {
      view.videoplayerStats.classList.remove("lg:hidden");
      view.videoplayerStats.classList.add("flex");
      view.statisticsTab.classList.remove("bg-gray-200");
      view.statisticsTab.classList.add("bg-gray-200");
      view.compareTab.classList.remove("bg-gray-200");
      view.compareStats.classList.remove("hidden");
      view.compareStats.classList.remove("lg:flex");
      view.compareStats.classList.add("hidden");
    };

    view.compareTab.onclick = () => {
      view.videoplayerStats.classList.remove("lg:hidden");
      view.videoplayerStats.classList.remove("flex");
      view.videoplayerStats.classList.add("lg:hidden");
      view.compareStats.classList.remove("lg:flex");
      view.compareStats.classList.add("lg:flex");
      view.statisticsTab.classList.remove("bg-gray-200");
      view.compareTab.classList.remove("bg-gray-200");
      view.compareTab.classList.add("bg-gray-200");
    };

    view.stats = {
      duration: document.getElementById("duration"),
      rtt: document.getElementById("rtt"),
      rttShort: document.getElementById("rtt-short"),
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
      avgJitterBufferDelayShort: document.getElementById(
        "avg-jitter-buffer-delay-short"
      ),
      freezeCount: document.getElementById("freeze-count"),
      freezeDuration: document.getElementById("freeze-duration"),
      freezeDurationShort: document.getElementById("freeze-duration-short"),

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

    view.recorder = {};

    // declare custom fields
    view.whepEndpointBase = `${window.location.origin}`;
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

    view.compareBtn.onclick = () => compare(view);

    view.rttChart = createChart(
      document.getElementById("rtt-chart"),
      "RTT (ms)",
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

    // update size when div wrapping canvas changes its size
    const resizeObserver = new ResizeObserver(() => view.globe.updateSize());
    resizeObserver.observe(document.getElementById("cluster-view"));

    document.getElementById("localize").onclick = () => {
      navigator.geolocation.getCurrentPosition((position) => {
        label = {
          text: "YOU",
          type: "client",
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        };
        view.globe.addLabels([label]);
      });
    };

    document.getElementById("rotate").onclick = () => {
      view.globe.controls.autoRotate = !view.globe.controls.autoRotate;
    };

    console.log("Started globe animation");
  },
};
