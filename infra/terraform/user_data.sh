#!/bin/bash
# EC2 User Data — Recommendation Engine + Datadog Agent
# Runs on Amazon Linux 2023 at boot.
set -euo pipefail

LOG=/var/log/wastehunter-init.log
exec > >(tee -a $LOG) 2>&1
echo "=== WasteHunter test app init $(date) ==="

# ── 1. System update ──────────────────────────────────────────────────────────
dnf update -y
dnf install -y python3

# ── 2. Install the recommendation engine ─────────────────────────────────────
mkdir -p /opt/rec-engine

cat > /opt/rec-engine/rec_engine.py << 'PYEOF'
import json, random, time, os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

START_TIME = time.time()
REQUEST_COUNT = 0

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global REQUEST_COUNT
        REQUEST_COUNT += 1
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        if parsed.path == "/health":
            self._respond(200, {"status": "ok", "uptime_s": int(time.time() - START_TIME)})
        elif parsed.path == "/api/recommend":
            n = int(params.get("n", ["5"])[0])
            t0 = time.time()
            items = [{"id": f"item-{i}", "score": round(random.random(), 4)} for i in random.sample(range(1000), min(n, 20))]
            self._respond(200, {"items": items, "latency_ms": round((time.time() - t0) * 1000, 2)})
        elif parsed.path == "/metrics":
            self._respond(200, {"requests_total": REQUEST_COUNT, "uptime_s": int(time.time() - START_TIME)})
        else:
            self._respond(404, {"error": "not found"})
    def _respond(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, fmt, *args):
        pass

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
PYEOF

# ── 3. systemd service for the app ───────────────────────────────────────────
cat > /etc/systemd/system/rec-engine.service << 'SVCEOF'
[Unit]
Description=Recommendation Engine Test App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/rec-engine/rec_engine.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable rec-engine
systemctl start rec-engine
echo "✓ rec-engine started on :8080"

# ── 4. Install Datadog Agent ──────────────────────────────────────────────────
DD_API_KEY="${dd_api_key}"
DD_SITE="${dd_site}"

DD_API_KEY="$DD_API_KEY" DD_SITE="$DD_SITE" \
  bash -c "$(curl -L https://s3.amazonaws.com/dd-agent-bootstrap/datadog-agent7-latest.sh)" || {
  echo "Datadog install via s3 failed, trying install.datadoghq.com..."
  DD_API_KEY="$DD_API_KEY" DD_SITE="$DD_SITE" \
    bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
}

# ── 5. Configure Datadog agent tags ──────────────────────────────────────────
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

cat > /etc/datadog-agent/datadog.yaml << DDEOF
api_key: $DD_API_KEY
site: $DD_SITE

hostname: wastehunter-rec-engine-$INSTANCE_ID

tags:
  - env:test
  - service:recommendation-engine
  - team:platform
  - managed_by:wastehunter
  - instance_id:$INSTANCE_ID
  - instance_type:$INSTANCE_TYPE
  - region:$REGION

# Report CPU, memory, network every 15s
min_collection_interval: 15

logs_enabled: false
DDEOF

systemctl restart datadog-agent
echo "✓ Datadog agent configured for $INSTANCE_ID ($INSTANCE_TYPE) in $REGION"
echo "=== Init complete $(date) ==="
