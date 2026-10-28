#!/usr/bin/env python3
"""A recording reverse proxy in front of the site, for the e2e.

    recording-proxy.py <upstream-origin> <port-file> <log-file>

Every request the e2e's browser-side client sends goes through it: it
forwards the request to <upstream-origin> unchanged (method, path, query,
headers, body) and returns the answer unchanged, and appends one JSON line
per request to <log-file> — `{"method", "path", "headers", "body"}`, the
body base64-encoded. That log is everything the Worker was sent, so the e2e
can assert that no request — path, query, header or body — carried a
document's key: the share flow keeps it in the link's fragment, which a
client never sends.

It binds a free port on 127.0.0.1 and writes it to <port-file>. It is
threaded, so concurrent requests reach the Worker concurrently.
"""
import base64
import http.client
import json
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

upstream = urllib.parse.urlparse(sys.argv[1])
port_file, log_file = sys.argv[2], sys.argv[3]
lock = threading.Lock()
HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer"}


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def forward(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        with lock, open(log_file, "a") as log:
            log.write(json.dumps({"method": self.command, "path": self.path, "headers": headers,
                                  "body": base64.b64encode(body).decode()}) + "\n")
        conn = http.client.HTTPConnection(upstream.hostname, upstream.port, timeout=60)
        try:
            conn.request(self.command, self.path, body=body or None, headers=headers)
            r = conn.getresponse()
            data = r.read()
            self.send_response(r.status, r.reason)
            for k, v in r.getheaders():
                if k.lower() not in HOP and k.lower() != "content-length":
                    self.send_header(k, v)
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        finally:
            conn.close()

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = forward


server = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
server.daemon_threads = True
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
