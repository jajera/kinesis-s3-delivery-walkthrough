#!/usr/bin/env python3
"""Build a self-contained HTML delivery report for the lab (read-only).

Uses the AWS CLI on PATH with AWS_PROFILE / AWS_REGION — same auth as demo.sh.
Writes .lab/viz/report.html and prints its path.
"""

from __future__ import annotations

import gzip
import io
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE_PATH = Path(os.environ.get("KDS_LAB_STATE", ROOT / ".lab-state.json"))
OUT_DIR = Path(os.environ.get("KDS_VIZ_DIR", ROOT / ".lab" / "viz"))
OUT_HTML = OUT_DIR / "report.html"


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def aws(*args: str, binary: bool = False):
    profile = os.environ.get("AWS_PROFILE", "sandbox")
    region = os.environ.get("AWS_REGION", "ap-southeast-2")
    cmd = ["aws", "--profile", profile, "--region", region, *args]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        if "Token has expired" in err or ("sso" in err.lower() and "refresh" in err.lower()):
            die(f"AWS SSO token expired. Run: aws sso login --profile {profile}")
        die(err or f"aws {' '.join(args)} failed")
    return proc.stdout if binary else proc.stdout.decode("utf-8")


def aws_json(*args: str):
    out = aws(*args)
    return json.loads(out) if out.strip() else {}


def aws_text(*args: str) -> str:
    return aws(*args, "--output", "text").strip()


def load_state() -> dict:
    if not STATE_PATH.is_file():
        die(f"No lab state at {STATE_PATH}. Run ./scripts/demo.sh up first.")
    return json.loads(STATE_PATH.read_text())


def list_objects(bucket: str) -> list[dict]:
    out: list[dict] = []
    token: str | None = None
    while True:
        args = ["s3api", "list-objects-v2", "--bucket", bucket, "--prefix", "data/"]
        if token:
            args.extend(["--continuation-token", token])
        data = aws_json(*args)
        out.extend(data.get("Contents") or [])
        if not data.get("IsTruncated"):
            break
        token = data.get("NextContinuationToken")
        if not token or len(out) >= 5000:
            break
    return out


def metric_points(name: str, stream: str, channel: str, channel_id: str, stat: str) -> list[dict]:
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=2)
    data = aws_json(
        "cloudwatch",
        "get-metric-statistics",
        "--namespace",
        "AWS/Kinesis",
        "--metric-name",
        name,
        "--dimensions",
        f"Name=StreamName,Value={stream}",
        f"Name=ChannelName,Value={channel}",
        f"Name=ChannelId,Value={channel_id}",
        "--start-time",
        start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "--end-time",
        end.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "--period",
        "300",
        "--statistics",
        stat,
    )
    points = sorted(data.get("Datapoints") or [], key=lambda p: p["Timestamp"])
    return [
        {
            "t": p["Timestamp"],
            "v": float(p[stat]),
        }
        for p in points
    ]


def peek(bucket: str, key: str) -> str:
    raw = aws("s3", "cp", f"s3://{bucket}/{key}", "-", binary=True)
    if key.endswith(".gz") or raw[:2] == b"\x1f\x8b":
        raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
    return raw.decode("utf-8", errors="replace").strip()[:4000]


def s3_console_url(bucket: str, region: str) -> str:
    return (
        f"https://s3.console.aws.amazon.com/s3/buckets/{bucket}"
        f"?region={region}&prefix=data/&showversions=false"
    )


def cw_console_url(region: str, stream: str, channel: str, channel_id: str) -> str:
    def enc(s: str) -> str:
        return s.replace("/", "*2f").replace(".", "*2e").replace("-", "*2d")

    ns, ok, fail = enc("AWS/Kinesis"), enc("DeliveryToS3.SuccessfulRecordCount"), enc(
        "DeliveryToS3.FailedRecordCount"
    )
    st, ch, cid, reg = enc(stream), enc(channel), enc(channel_id), enc(region)
    return (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}"
        f"#metricsV2:graph=~(view~'timeSeries~stacked~false~region~'{reg}"
        f"~start~'-PT2H~end~'P0D~stat~'Sum~period~300~metrics~("
        f"~(~'{ns}~'{ok}~'StreamName~'{st}~'ChannelName~'{ch}~'ChannelId~'{cid})"
        f"~(~'.~'{fail}~'StreamName~'{st}~'ChannelName~'{ch}~'ChannelId~'{cid})))"
    )


def render(html: str, data: dict) -> str:
    # Inject JSON; escape < so a payload cannot break out of </script>.
    payload = json.dumps(data, indent=2).replace("<", "\\u003c")
    return html.replace("/*__DATA__*/", payload)


TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Kinesis → S3 delivery · lab report</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Manrope:wght@400;500;600;700&family=Outfit:wght@600;700;800&display=swap" rel="stylesheet" />
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
  <style>
    :root {
      --bg: #071014;
      --bg-elev: #0b171c;
      --ink: #eef8fa;
      --muted: #8 Pan7a86;
      --line: rgb(34 211 238 / 16%);
      --accent: #22d3ee;
      --accent-soft: #67e8f9;
      --ok: #34d399;
      --bad: #fb7185;
      --warn: #fbbf24;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0; min-height: 100%;
      background:
        radial-gradient(1200px 600px at 10% -10%, rgb(34 211 238 / 12%), transparent 55%),
        radial-gradient(900px 500px at 90% 0%, rgb(15 118 110 / 18%), transparent 50%),
        var(--bg);
      color: var(--ink);
      font-family: Manrope, ui-sans-serif, system-ui, sans-serif;
      font-size: 15px;
      line-height: 1.5;
    }
    .wrap {
      max-width: 1080px;
      margin: 0 auto;
      padding: 2.5rem 1.5rem 4rem;
    }
    header {
      display: grid;
      gap: 0.75rem;
      padding-bottom: 1.75rem;
      border-bottom: 1px solid var(--line);
      margin-bottom: 2rem;
    }
    .eyebrow {
      font-size: 0.72rem;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: var(--accent-soft);
      font-weight: 600;
    }
    h1 {
      font-family: Outfit, Manrope, sans-serif;
      font-weight: 800;
      font-size: clamp(1.8rem, 4vw, 2.6rem);
      letter-spacing: -0.03em;
      margin: 0;
      line-height: 1.1;
    }
    .lede {
      color: #b7cdd4;
      max-width: 42rem;
      margin: 0;
    }
    .meta {
      display: flex; flex-wrap: wrap; gap: 0.75rem 1.25rem;
      color: #8aa0a8;
      font-size: 0.85rem;
    }
    .meta code {
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.8rem;
      color: var(--ink);
      background: rgb(255 255 255 / 4%);
      padding: 0.15rem 0.4rem;
      border-radius: 4px;
    }
    .actions {
      display: flex; flex-wrap: wrap; gap: 0.6rem;
      margin-top: 0.5rem;
    }
    a.btn {
      display: inline-flex; align-items: center; gap: 0.4rem;
      text-decoration: none;
      color: var(--bg);
      background: var(--accent);
      font-weight: 700;
      font-size: 0.85rem;
      padding: 0.55rem 0.9rem;
      border-radius: 999px;
    }
    a.btn.secondary {
      background: transparent;
      color: var(--accent-soft);
      border: 1px solid var(--line);
    }
    section { margin: 2.25rem 0; }
    section h2 {
      font-family: Outfit, Manrope, sans-serif;
      font-size: 1.05rem;
      font-weight: 700;
      letter-spacing: -0.01em;
      margin: 0 0 1rem;
    }
    .pipeline {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 0.75rem;
    }
    @media (max-width: 800px) {
      .pipeline { grid-template-columns: 1fr 1fr; }
    }
    .stage {
      padding: 1rem 1.1rem;
      background: var(--bg-elev);
      border: 1px solid var(--line);
      border-radius: 10px;
      border-left-width: 3px;
    }
    .stage[data-ok="true"] { border-left-color: var(--ok); }
    .stage[data-ok="false"] { border-left-color: var(--bad); }
    .stage .label {
      font-size: 0.68rem; letter-spacing: 0.1em; text-transform: uppercase;
      color: #8aa0a8; margin-bottom: 0.35rem;
    }
    .stage .value {
      font-family: Outfit, Manrope, sans-serif;
      font-weight: 700; font-size: 1.15rem;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 0.75rem;
    }
    @media (max-width: 800px) {
      .stats { grid-template-columns: 1fr 1fr; }
    }
    .stat {
      padding: 1rem 1.1rem;
      border-bottom: 1px solid var(--line);
    }
    .stat .k { font-size: 0.72rem; letter-spacing: 0.08em; text-transform: uppercase; color: #8aa0a8; }
    .stat .v {
      font-family: Outfit, Manrope, sans-serif;
      font-size: 1.45rem; font-weight: 700; margin-top: 0.2rem;
    }
    .chart-panel {
      background: var(--bg-elev);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1rem 1rem 0.5rem;
    }
    .chart-wrap { position: relative; height: 320px; }
    .split {
      display: grid;
      grid-template-columns: 1.4fr 1fr;
      gap: 1.25rem;
    }
    @media (max-width: 900px) {
      .split { grid-template-columns: 1fr; }
    }
    pre.payload {
      margin: 0;
      padding: 1rem;
      background: #051015;
      border: 1px solid var(--line);
      border-radius: 10px;
      overflow: auto;
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.78rem;
      color: #d4e8ee;
      max-height: 280px;
    }
    .key {
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.72rem;
      color: #8aa0a8;
      word-break: break-all;
      margin-bottom: 0.6rem;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.85rem;
    }
    th, td {
      text-align: left;
      padding: 0.55rem 0.4rem;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    th {
      font-size: 0.68rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #8aa0a8;
      font-weight: 600;
    }
    td.mono {
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.72rem;
      word-break: break-all;
    }
    footer {
      margin-top: 3rem;
      padding-top: 1.25rem;
      border-top: 1px solid var(--line);
      color: #8aa0a8;
      font-size: 0.8rem;
    }
    .empty {
      color: #8aa0a8;
      padding: 1.5rem;
      border: 1px dashed var(--line);
      border-radius: 10px;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="eyebrow">Lab report · read-only</div>
      <h1>Kinesis → S3 delivery</h1>
      <p class="lede">Managed channel health and objects landed in the destination prefix for this lab run.</p>
      <div class="meta">
        <span>Lab <code id="suffix"></code></span>
        <span>Region <code id="region"></code></span>
        <span>Generated <code id="generated"></code></span>
      </div>
      <div class="actions">
        <a class="btn" id="s3-link" href="#" target="_blank" rel="noopener">Open S3 prefix</a>
        <a class="btn secondary" id="cw-link" href="#" target="_blank" rel="noopener">Open CloudWatch graph</a>
      </div>
    </header>

    <section>
      <h2>Pipeline</h2>
      <div class="pipeline" id="pipeline"></div>
    </section>

    <section>
      <h2>At a glance</h2>
      <div class="stats" id="stats"></div>
    </section>

    <section>
      <h2>Delivery metrics (last 2 hours)</h2>
      <div class="chart-panel">
        <div class="chart-wrap"><canvas id="deliveryChart"></canvas></div>
      </div>
    </section>

    <section class="split">
      <div>
        <h2>Freshness</h2>
        <div class="chart-panel">
          <div class="chart-wrap" style="height:240px"><canvas id="freshChart"></canvas></div>
        </div>
      </div>
      <div>
        <h2>Latest record</h2>
        <div class="key" id="latest-key"></div>
        <pre class="payload" id="latest-payload">—</pre>
      </div>
    </section>

    <section>
      <h2>Recent objects</h2>
      <div id="objects"></div>
    </section>

    <footer>
      Re-run <code>./scripts/demo.sh viz</code> to refresh. Creates no AWS resources.
      Tear down with <code>./scripts/demo.sh down</code> when finished.
    </footer>
  </div>

  <script>
    const DATA = /*__DATA__*/;

    document.getElementById('suffix').textContent = DATA.suffix;
    document.getElementById('region').textContent = DATA.region;
    document.getElementById('generated').textContent = DATA.generated;
    document.getElementById('s3-link').href = DATA.links.s3;
    document.getElementById('cw-link').href = DATA.links.cloudwatch;

    const pipeline = document.getElementById('pipeline');
    for (const s of DATA.pipeline) {
      const el = document.createElement('div');
      el.className = 'stage';
      el.dataset.ok = String(!!s.ok);
      el.innerHTML = `<div class="label">${s.label}</div><div class="value">${s.value}</div>`;
      pipeline.appendChild(el);
    }

    const stats = document.getElementById('stats');
    for (const s of DATA.stats) {
      const el = document.createElement('div');
      el.className = 'stat';
      el.innerHTML = `<div class="k">${s.label}</div><div class="v">${s.value}</div>`;
      stats.appendChild(el);
    }

    document.getElementById('latest-key').textContent = DATA.latest.key || '—';
    document.getElementById('latest-payload').textContent = DATA.latest.payload || 'No objects under data/ yet.';

    const objHost = document.getElementById('objects');
    if (!DATA.objects.length) {
      objHost.innerHTML = '<div class="empty">No objects yet. Wait ≥ DataFreshnessInSeconds (default 300s) after produce, then re-run viz.</div>';
    } else {
      const rows = DATA.objects.map(o =>
        `<tr><td>${o.when}</td><td>${o.size}</td><td class="mono">${o.key}</td></tr>`
      ).join('');
      objHost.innerHTML = `<table><thead><tr><th>Last modified (UTC)</th><th>Bytes</th><th>Key</th></tr></thead><tbody>${rows}</tbody></table>`;
    }

    const grid = 'rgb(34 211 238 / 10%)';
    const tick = '#8aa0a8';
    Chart.defaults.color = tick;
    Chart.defaults.borderColor = grid;
    Chart.defaults.font.family = 'Manrope, sans-serif';

    const labels = DATA.charts.labels;
    const hasMetrics = labels.length > 0;
    if (!hasMetrics) {
      document.getElementById('deliveryChart').parentElement.innerHTML =
        '<div class="empty">No DeliveryToS3 datapoints in the last 2 hours yet.</div>';
      document.getElementById('freshChart').parentElement.innerHTML =
        '<div class="empty">No freshness datapoints yet.</div>';
    } else {
    new Chart(document.getElementById('deliveryChart'), {
      type: 'line',
      data: {
        labels,
        datasets: [
          {
            label: 'Successful',
            data: DATA.charts.successful,
            borderColor: '#22d3ee',
            backgroundColor: 'rgb(34 211 238 / 18%)',
            fill: true,
            tension: 0.25,
            pointRadius: 2,
            borderWidth: 2,
            spanGaps: true,
          },
          {
            label: 'Failed',
            data: DATA.charts.failed,
            borderColor: '#fb7185',
            backgroundColor: 'transparent',
            tension: 0.25,
            pointRadius: 2,
            borderWidth: 2,
            spanGaps: true,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top', align: 'end', labels: { boxWidth: 10, usePointStyle: true } },
        },
        scales: {
          x: { grid: { display: false }, ticks: { maxRotation: 0, autoSkipPadding: 16 } },
          y: { beginAtZero: true, grid: { color: grid }, title: { display: true, text: 'Records / 5 min' } },
        },
      },
    });

    new Chart(document.getElementById('freshChart'), {
      type: 'line',
      data: {
        labels,
        datasets: [{
          label: 'DataFreshness (s)',
          data: DATA.charts.freshness,
          borderColor: '#fbbf24',
          backgroundColor: 'rgb(251 191 36 / 12%)',
          fill: true,
          tension: 0.25,
          pointRadius: 2,
          borderWidth: 2,
          spanGaps: true,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { grid: { display: false }, ticks: { maxRotation: 0, autoSkipPadding: 16 } },
          y: { beginAtZero: true, grid: { color: grid }, title: { display: true, text: 'Seconds' } },
        },
      },
    });
    }
  </script>
</body>
</html>
"""


def main() -> None:
    state = load_state()
    profile = os.environ.get("AWS_PROFILE") or state.get("profile") or "sandbox"
    region = os.environ.get("AWS_REGION") or state.get("region") or "ap-southeast-2"
    os.environ["AWS_PROFILE"] = profile
    os.environ["AWS_REGION"] = region

    bucket = state["bucketName"]
    stream = state["streamName"]
    channel = state["channelName"]
    channel_id = state.get("channelId") or ""
    channel_arn = state.get("channelArn") or ""
    suffix = state.get("suffix") or ""

    stream_status = aws_text(
        "kinesis",
        "describe-stream-summary",
        "--stream-name",
        stream,
        "--query",
        "StreamDescriptionSummary.StreamStatus",
    )
    channel_status = "—"
    if channel_arn:
        channel_status = aws_text(
            "kinesis",
            "describe-channel",
            "--channel-arn",
            channel_arn,
            "--query",
            "ChannelDescription.ChannelStatus",
        )
    producer_fn = f"kds-s3-demo-{suffix}-producer"
    proc = subprocess.run(
        [
            "aws",
            "--profile",
            profile,
            "--region",
            region,
            "lambda",
            "get-function",
            "--function-name",
            producer_fn,
            "--query",
            "Configuration.State",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
    )
    producer_status = proc.stdout.strip() if proc.returncode == 0 else "not found"

    objects = list_objects(bucket)
    objects_sorted = sorted(objects, key=lambda o: o["LastModified"])

    ok = metric_points(
        "DeliveryToS3.SuccessfulRecordCount", stream, channel, channel_id, "Sum"
    ) if channel_id else []
    fail = metric_points(
        "DeliveryToS3.FailedRecordCount", stream, channel, channel_id, "Sum"
    ) if channel_id else []
    fresh = metric_points(
        "DeliveryToS3.DataFreshness", stream, channel, channel_id, "Average"
    ) if channel_id else []

    # Align series on union of timestamps
    times = sorted({p["t"] for p in ok + fail + fresh})
    def series(points: list[dict]) -> list[float | None]:
        m = {p["t"]: p["v"] for p in points}
        return [m.get(t) for t in times]

    def fmt_ts(ts: str) -> str:
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc).strftime("%H:%M")
        except Exception:
            return ts

    labels = [fmt_ts(t) for t in times]

    latest_key = ""
    latest_payload = ""
    if objects_sorted:
        latest_key = objects_sorted[-1]["Key"]
        try:
            latest_payload = peek(bucket, latest_key)
        except SystemExit:
            latest_payload = "(could not download)"

    first = objects_sorted[0]["LastModified"] if objects_sorted else "—"
    last = objects_sorted[-1]["LastModified"] if objects_sorted else "—"
    total_bytes = sum(int(o.get("Size") or 0) for o in objects)

    def short_when(ts: str) -> str:
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            return ts

    data = {
        "suffix": suffix,
        "region": region,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "links": {
            "s3": s3_console_url(bucket, region),
            "cloudwatch": cw_console_url(region, stream, channel, channel_id)
            if channel_id
            else s3_console_url(bucket, region),
        },
        "pipeline": [
            {"label": "Producer", "value": producer_status, "ok": producer_status == "Active"},
            {"label": "Stream", "value": stream_status, "ok": stream_status == "ACTIVE"},
            {"label": "Channel", "value": channel_status, "ok": channel_status == "ACTIVE"},
            {"label": "S3", "value": "data/", "ok": bool(objects_sorted)},
        ],
        "stats": [
            {"label": "Objects", "value": str(len(objects))},
            {"label": "Bytes", "value": f"{total_bytes:,}"},
            {"label": "First", "value": short_when(first) if objects_sorted else "—"},
            {"label": "Latest", "value": short_when(last) if objects_sorted else "—"},
        ],
        "charts": {
            "labels": labels,
            "successful": series(ok),
            "failed": series(fail),
            "freshness": series(fresh),
        },
        "latest": {"key": latest_key, "payload": latest_payload},
        "objects": [
            {
                "when": short_when(o["LastModified"]),
                "size": o.get("Size", 0),
                "key": o["Key"],
            }
            for o in reversed(objects_sorted[-25:])
        ],
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_HTML.write_text(render(TEMPLATE, data), encoding="utf-8")
    print(OUT_HTML)


if __name__ == "__main__":
    main()
