"""
Recommendation Engine — Test Application
=========================================
A minimal HTTP server deployed on AWS EC2 to simulate a real but idle service.
Runs at ~1-3% CPU on t3.medium, which Datadog reports as idle waste.
WasteHunter will detect this and recommend downsizing to t3.micro.

Endpoints:
  GET /health              → {"status": "ok"}
  GET /api/recommend?n=5   → {"items": [...], "latency_ms": ...}
  GET /metrics             → {"requests_total": ..., "uptime_s": ...}
"""

import json
import random
import time
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
            # Minimal computation — intentionally idle (< 2% CPU)
            items = [
                {"id": f"item-{i}", "score": round(random.random(), 4), "name": f"Product {i}"}
                for i in random.sample(range(1000), min(n, 20))
            ]
            self._respond(200, {
                "items": items,
                "count": len(items),
                "latency_ms": round((time.time() - t0) * 1000, 2),
            })

        elif parsed.path == "/metrics":
            self._respond(200, {
                "requests_total": REQUEST_COUNT,
                "uptime_s": int(time.time() - START_TIME),
                "instance_type": "t3.medium",   # WasteHunter reads this tag
            })

        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, code: int, body: dict):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass  # suppress access logs to keep CPU near zero


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), Handler)
    print(f"Recommendation Engine listening on :8080 (pid={__import__('os').getpid()})")
    server.serve_forever()
