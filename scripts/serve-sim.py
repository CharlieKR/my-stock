#!/usr/bin/env python3
"""Show the booted My Stock iOS simulator inside Codex's local browser."""

import argparse
import json
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PAGE = """<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>My Stock · iPhone Simulator</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#101114;color:#f5f5f7;font:14px -apple-system,BlinkMacSystemFont,sans-serif}
main{min-height:100vh;display:grid;place-items:center;padding:18px}.viewer{width:min(100%,460px)}
header{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;color:#b5b7c0}
strong{color:#f5f5f7;font-size:15px}#state{font-size:12px}.phone{width:100%;display:block;border-radius:35px;border:5px solid #2e3036;background:#17191d;box-shadow:0 24px 70px #0009}
footer{text-align:center;color:#8e919c;font-size:12px;margin-top:12px}
</style></head><body><main><div class="viewer"><header><strong>My Stock · iPhone Simulator</strong><span id="state">연결 중</span></header>
<img id="screen" class="phone" alt="iPhone 시뮬레이터 화면"><footer>실행 중인 iOS 시뮬레이터의 실시간 화면</footer></div></main>
<script>
const screen=document.getElementById('screen'),state=document.getElementById('state');
async function refresh(){try{const response=await fetch('/frame.jpg?t='+Date.now(),{cache:'no-store'});if(!response.ok)throw Error();
const blob=await response.blob(),url=URL.createObjectURL(blob),previous=screen.src;screen.src=url;
if(previous.startsWith('blob:'))URL.revokeObjectURL(previous);state.textContent='연결됨';}
catch{state.textContent='시뮬레이터 연결 대기 중';}setTimeout(refresh,1100)}refresh();
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            data, kind = PAGE.encode(), "text/html; charset=utf-8"
        elif path == "/health":
            data, kind = json.dumps({"device": self.server.device}).encode(), "application/json"
        elif path == "/frame.jpg":
            with self.server.capture_lock:
                if time.monotonic() - self.server.last_capture > 0.8:
                    with tempfile.TemporaryDirectory(prefix="my-stock-sim-") as temp_dir:
                        frame_path = Path(temp_dir) / "frame.jpg"
                        result = subprocess.run(
                            ["xcrun", "simctl", "io", self.server.device, "screenshot", "--type=jpeg", str(frame_path)],
                            capture_output=True, timeout=10, check=False,
                        )
                        if result.returncode != 0:
                            self.send_error(503, "Simulator screenshot unavailable")
                            return
                        self.server.frame = frame_path.read_bytes()
                    self.server.last_capture = time.monotonic()
                data, kind = self.server.frame, "image/jpeg"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--port", type=int, default=3200)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.device = args.device
    server.capture_lock = threading.Lock()
    server.last_capture = 0
    server.frame = b""
    server.serve_forever()
