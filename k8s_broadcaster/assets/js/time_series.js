export class TimeSeries {
  constructor(maxPoints = 60) {
    this.x = [];
    this.y = [];
    this.maxPoints = maxPoints;
  }

  length() {
    return this.x.length;
  }

  push(x, y) {
    this.x.push(x);
    this.y.push(y);

    if (this.length() > this.maxPoints) {
      this.x.shift();
      this.y.shift();
    }
  }

  populateLastMinute(startTime = Date.now()) {
    const timestamps = [];
    for (let i = 0; i < 60; i++) {
      const date = new Date(startTime - i * 1000);
      const timestamp =
        date.getHours() + ":" + date.getMinutes() + ":" + date.getSeconds();
      timestamps.push(timestamp);
    }

    const values = [];
    for (let i = 0; i < 60; i++) {
      values.push(0);
    }

    this.x = timestamps;
    this.y = values;

    return this;
  }
}
