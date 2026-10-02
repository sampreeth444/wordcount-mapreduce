#!/usr/bin/env python3
"""
Live word count server.

Serves the project folder on localhost and exposes POST /api/run, which
takes some text, uploads it to HDFS, runs the real Hadoop MapReduce job
(target/wordcount-1.0.jar), and returns the counts and job counters.

Usage:
    python3 server.py            # http://localhost:8000/live.html
    python3 server.py --port 9000
"""
import argparse
import functools
import getpass
import http.server
import json
import os
import re
import socketserver
import subprocess
import tempfile
import threading
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
JAR = os.path.join(HERE, "target", "wordcount-1.0.jar")
USER = getpass.getuser()
MAX_BYTES = 5_000_000
LOCK = threading.Lock()  # one Hadoop job at a time on a single-node cluster

COUNTERS = {
    "map_input_records": "Map input records",
    "map_output_records": "Map output records",
    "combine_input_records": "Combine input records",
    "combine_output_records": "Combine output records",
    "shuffle_bytes": "Reduce shuffle bytes",
    "reduce_input_records": "Reduce input records",
    "reduce_output_records": "Reduce output records",
}


def sh(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError(f"Command not found: {cmd[0]}. Open a new terminal or run: source ~/.bashrc")
    if res.returncode != 0:
        tail = "\n".join((res.stderr or res.stdout).strip().splitlines()[-6:])
        raise RuntimeError(f"{' '.join(cmd[:3])} failed:\n{tail}")
    return res


def parse_counters(log):
    found = {}
    for key, label in COUNTERS.items():
        m = re.search(rf"{label}=(\d+)", log)
        found[key] = int(m.group(1)) if m else 0
    return found


def run_job(text, combiner):
    if not os.path.exists(JAR):
        raise RuntimeError("target/wordcount-1.0.jar not found. Run: mvn clean package")
    base = f"/user/{USER}/live/{uuid.uuid4().hex[:8]}"
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(text)
        local = f.name
    try:
        sh(["hdfs", "dfs", "-mkdir", "-p", base + "/input"])
        sh(["hdfs", "dfs", "-put", "-f", local, base + "/input/input.txt"])
        cmd = ["hadoop", "jar", JAR, base + "/input", base + "/output"]
        if not combiner:
            cmd.append("--no-combiner")
        start = time.time()
        res = sh(cmd)
        seconds = round(time.time() - start, 1)
        counters = parse_counters(res.stderr + res.stdout)
        out = sh(["hdfs", "dfs", "-cat", base + "/output/part-r-00000"]).stdout
    finally:
        os.unlink(local)
        subprocess.run(["hdfs", "dfs", "-rm", "-r", "-f", base], capture_output=True)

    words = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].isdigit():
            words.append([parts[0], int(parts[1])])
    words.sort(key=lambda w: (-w[1], w[0]))
    return {"words": words, "counters": counters, "seconds": seconds, "combiner": combiner}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HERE, **kwargs)

    def reply(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/run":
            return self.reply(404, {"error": "Unknown endpoint"})
        try:
            size = int(self.headers.get("Content-Length", 0))
            if size > MAX_BYTES + 1000:
                return self.reply(413, {"error": "Text is too large. The limit is 5 MB."})
            data = json.loads(self.rfile.read(size))
            text = data.get("text", "")
            if not re.search(r"[A-Za-z]", text):
                return self.reply(400, {"error": "The text has no letters to count. Paste some words and try again."})
            if len(text.encode("utf-8")) > MAX_BYTES:
                return self.reply(413, {"error": "Text is too large. The limit is 5 MB."})
            if not LOCK.acquire(blocking=False):
                return self.reply(429, {"error": "A job is already running. Wait for it to finish."})
            try:
                result = run_job(text, bool(data.get("combiner", True)))
            finally:
                LOCK.release()
            self.reply(200, result)
        except Exception as err:  # report any failure to the page
            self.reply(500, {"error": str(err)})

    def log_message(self, fmt, *args):
        text = str(fmt % args) if args else str(fmt)
        if "/api/" in text:
            super().log_message(fmt, *args)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    with socketserver.ThreadingTCPServer(("", args.port), Handler) as server:
        print(f"Open http://localhost:{args.port}/live.html in your browser. Press Ctrl+C to stop.")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()