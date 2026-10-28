#!/usr/bin/env python3
"""A stand-in for Cloudflare D1's REST API, over a real SQLite file.

    d1-api.py <sqlite-file> <port-file> --account <id> --database <id> --token <token>

Serves the one endpoint the migration runner calls (packages/db's
D1ApiAdapter):

    POST /client/v4/accounts/<account>/d1/database/<database>/query
    Authorization: Bearer <token>
    {"sql": "...", "params": [...]}

and answers the way D1 does: `{"success": true, "result": [{"results": [rows],
"success": true}]}`, or `{"success": false, "errors": [{"code", "message"}]}`
with a 4xx. A request for another account or database, or with another token,
is refused as Cloudflare refuses it, so the e2e proves the runner sends what
the component's secretEnv resolves — not merely that it sent something.

It binds a free port on 127.0.0.1 and writes it to <port-file>; the runner is
pointed at it with CLOUDFLARE_API_BASE_URL (wrangler's own override). SQLite is
D1's engine, so the migrations meet the semantics they meet in production.
Every statement autocommits, as each D1 query does.
"""
import argparse
import json
import re
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ap = argparse.ArgumentParser()
ap.add_argument("db")
ap.add_argument("port_file")
ap.add_argument("--account", required=True)
ap.add_argument("--database", required=True)
ap.add_argument("--token", required=True)
args = ap.parse_args()

conn = sqlite3.connect(args.db, isolation_level=None, check_same_thread=False)
conn.row_factory = sqlite3.Row
PATH = re.compile(r"^/client/v4/accounts/([^/]+)/d1/database/([^/]+)/query$")


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def fail(self, status, code, message):
        self.reply(status, {"success": False, "errors": [{"code": code, "message": message}], "result": []})

    def do_POST(self):  # noqa: N802 (http.server's name)
        m = PATH.match(self.path)
        if not m:
            return self.fail(404, 7003, f"no route for {self.path}")
        if self.headers.get("authorization") != f"Bearer {args.token}":
            return self.fail(403, 10000, "Authentication error")
        if m.group(1) != args.account:
            return self.fail(403, 10000, f"Authentication error (account {m.group(1)})")
        if m.group(2) != args.database:
            return self.fail(404, 7404, f"database {m.group(2)} not found")
        body = json.loads(self.rfile.read(int(self.headers.get("content-length") or 0)) or b"{}")
        try:
            rows = [dict(r) for r in conn.execute(body.get("sql") or "", body.get("params") or []).fetchall()]
        except sqlite3.Error as err:
            return self.fail(400, 7500, f"{err}: SQLITE_ERROR")
        self.reply(200, {"success": True, "errors": [], "result": [{"results": rows, "success": True}]})

    def log_message(self, fmt, *a):
        sys.stderr.write("d1-api: " + (fmt % a) + "\n")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(args.port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
