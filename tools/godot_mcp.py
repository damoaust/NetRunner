#!/usr/bin/env python3
"""Client for NetRunner's McpInteractionServer (autoload/mcp_interaction_server.gd).

Speaks the server's newline-delimited-JSON protocol over TCP 127.0.0.1:9090.
Sends ONE command, waits for its response, prints it as JSON. Exit code 1 on
an error response or timeout.

Usage:
  python3 tools/godot_mcp.py <command> ['<params-json>'] [options]

Examples:
  python3 tools/godot_mcp.py get_scene_tree
  python3 tools/godot_mcp.py eval '{"code": "RunState.credits"}'
  python3 tools/godot_mcp.py click '{"x": 640, "y": 360}'
  python3 tools/godot_mcp.py screenshot --save shot.png
  python3 tools/godot_mcp.py get_property --wait-port 30 '{"path": "/root/Main", "property": "name"}'

The game (not the editor) hosts the server: it comes up when a scene is
running. `screenshot` needs a real renderer — it fails under --headless.
"""

import argparse
import base64
import json
import socket
import sys
import time

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9090


def connect(host: str, port: int, wait_port: float):
    deadline = time.time() + wait_port
    while True:
        try:
            return socket.create_connection((host, port), timeout=2)
        except OSError:
            if time.time() >= deadline:
                sys.exit(
                    f"McpInteractionServer not listening on {host}:{port} — "
                    "start the game first (godot --path . or editor F5)"
                )
            time.sleep(0.5)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", help="e.g. get_scene_tree, eval, screenshot, click, key_press")
    ap.add_argument("params", nargs="?", default="{}", help="params as a JSON object, default {}")
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--timeout", type=float, default=30.0, help="seconds to wait for the response")
    ap.add_argument("--wait-port", type=float, default=0.0, help="wait up to N s for the server to listen")
    ap.add_argument("--save", metavar="PATH", help="with `screenshot`: decode base64 PNG data to PATH")
    args = ap.parse_args()

    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as e:
        sys.exit(f"params must be a JSON object: {e}")

    sock = connect(args.host, args.port, args.wait_port)
    request = {"command": args.command, "params": params}
    sock.sendall((json.dumps(request) + "\n").encode())

    buf = b""
    end = time.time() + args.timeout
    sock.settimeout(1.0)
    while time.time() < end:
        try:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                break
        except socket.timeout:
            continue
    sock.close()

    line = buf.split(b"\n", 1)[0].decode(errors="replace").strip()
    if not line:
        sys.exit(f"no response within {args.timeout}s — the server may be busy; retry with a longer --timeout")

    try:
        response = json.loads(line)
    except json.JSONDecodeError:
        sys.exit(f"non-JSON response: {line[:500]}")

    if args.save and isinstance(response.get("data"), str):
        with open(args.save, "wb") as f:
            f.write(base64.b64decode(response["data"]))
        print(f"saved {response.get('width')}x{response.get('height')} PNG to {args.save}")
        return

    print(json.dumps(response, indent=2, ensure_ascii=False))
    if "error" in response:
        sys.exit(1)


if __name__ == "__main__":
    main()