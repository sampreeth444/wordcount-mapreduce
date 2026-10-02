#!/usr/bin/env python3
"""
Builds dashboard.html from the real word-count output stored in HDFS,
then serves it on localhost.

Usage:
    python3 dashboard.py                      # read /user/<you>/output, serve on :8000
    python3 dashboard.py --port 9000
    python3 dashboard.py --output /user/sam/out_comb/part-r-00000
    python3 dashboard.py --no-serve           # only write dashboard.html
"""
import argparse
import getpass
import http.server
import json
import os
import socketserver
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read_hdfs(path):
    try:
        result = subprocess.run(
            ["hdfs", "dfs", "-cat", path],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        sys.exit("Could not find the 'hdfs' command. Open a new terminal, or run: source ~/.bashrc")
    except subprocess.CalledProcessError as err:
        sys.exit(
            f"Could not read {path} from HDFS.\n"
            "Check that Hadoop is running (jps) and that the job has been run.\n"
            f"{err.stderr.strip()}"
        )
    return result.stdout


def parse_counts(text):
    words = []
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].isdigit():
            words.append([parts[0], int(parts[1])])
    if not words:
        sys.exit("The output file was empty or not in 'word<TAB>count' format.")
    words.sort(key=lambda w: (-w[1], w[0]))
    return words


def main():
    user = getpass.getuser()
    ap = argparse.ArgumentParser(description="Build and serve the word count dashboard.")
    ap.add_argument("--output", default=f"/user/{user}/output/part-r-00000",
                    help="HDFS path of the job's output file")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--no-serve", action="store_true")
    args = ap.parse_args()

    with open(os.path.join(HERE, "metrics.json"), encoding="utf-8") as f:
        metrics = json.load(f)
    with open(os.path.join(HERE, "dashboard_template.html"), encoding="utf-8") as f:
        template = f.read()

    words = parse_counts(read_hdfs(args.output))
    payload = json.dumps({"words": words, "metrics": metrics}, separators=(",", ":"))
    payload = payload.replace("</", "<\\/")

    out_path = os.path.join(HERE, "dashboard.html")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(template.replace("__DATA__", payload))

    print(f"Read {len(words):,} distinct words ({sum(w[1] for w in words):,} total) from {args.output}")
    print(f"Wrote {out_path}")

    if args.no_serve:
        return

    os.chdir(HERE)
    handler = http.server.SimpleHTTPRequestHandler
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", args.port), handler) as server:
        print(f"\nOpen http://localhost:{args.port}/dashboard.html in your browser. Press Ctrl+C to stop.")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()