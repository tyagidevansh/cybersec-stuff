#!/usr/bin/env python3
"""Tiny exfil receiver: accepts POST /upload, replies 200. Attacker-side tool."""
from http.server import BaseHTTPRequestHandler, HTTPServer


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        print(f"RECEIVED {self.path} {len(body)} bytes", flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        print("LOG:", *a, flush=True)


HTTPServer(("0.0.0.0", 8000), H).serve_forever()
