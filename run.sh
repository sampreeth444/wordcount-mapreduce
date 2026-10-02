#!/usr/bin/env bash
# Starts Hadoop, runs the word count job on the sample books (first run only),
# then starts the web app on http://localhost:8000
#
# Usage:  bash run.sh            normal start
#         bash run.sh --rebuild  rerun the books job and rebuild dashboard.html
set -eu

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HADOOP_HOME="${HADOOP_HOME:-$HOME/hadoop}"
export PATH="$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin"
cd "$PROJECT_DIR"

if [ ! -x "$HADOOP_HOME/bin/hadoop" ] || [ ! -f target/wordcount-1.0.jar ]; then
  echo "Setup has not been completed. Run:  bash setup.sh"
  exit 1
fi

echo "==> Starting Hadoop"
sudo service ssh start > /dev/null
start-dfs.sh
start-yarn.sh
hdfs dfsadmin -safemode wait

for daemon in NameNode DataNode ResourceManager NodeManager; do
  if ! jps | grep -qw "$daemon"; then
    echo "ERROR: $daemon is not running. Check the logs in $HADOOP_HOME/logs"
    exit 1
  fi
done

if [ ! -f dashboard.html ] || [ "${1:-}" = "--rebuild" ]; then
  echo "==> Running word count on the sample books"
  IN="/user/$USER/input"
  OUT="/user/$USER/output"
  hdfs dfs -mkdir -p "$IN"
  hdfs dfs -put -f data/*.txt "$IN"
  hdfs dfs -rm -r -f "$OUT"
  hadoop jar target/wordcount-1.0.jar "$IN" "$OUT"
  echo ""
  echo "===== TOP 10 WORDS ====="
  hdfs dfs -cat "$OUT/part-r-00000" | sort -k2 -nr | head -10 || true
  python3 dashboard.py --no-serve
fi

echo ""
echo "==> Web app is starting"
echo "    Live app (run your own text):  http://localhost:8000/live.html"
echo "    Results on the sample books:   http://localhost:8000/dashboard.html"
echo "    Hadoop job monitor:            http://localhost:8088"
echo "    HDFS browser:                  http://localhost:9870"
echo ""
exec python3 server.py