#!/usr/bin/env bash
# One-time setup for Ubuntu / WSL Ubuntu.
# Installs Java 11, Maven, Hadoop 3.3.6 (single-node), configures it,
# downloads sample books and builds the project.
# Safe to run again: finished steps are skipped.
set -euo pipefail

HADOOP_VERSION=3.3.6
HADOOP_HOME="${HADOOP_HOME:-$HOME/hadoop}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: this script needs Ubuntu or Debian (on Windows, use WSL Ubuntu)."
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: do not run this as root. Run it as your normal user (it will ask for sudo when needed)."
  exit 1
fi

echo "==> [1/6] Installing Java 11, SSH, Maven, Python 3, wget"
sudo apt-get update -y
sudo apt-get install -y openjdk-11-jdk ssh wget maven python3
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"

echo "==> [2/6] Installing Hadoop $HADOOP_VERSION into $HADOOP_HOME"
if [ ! -x "$HADOOP_HOME/bin/hadoop" ]; then
  TARBALL="/tmp/hadoop-$HADOOP_VERSION.tar.gz"
  MAIN="https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
  ARCHIVE="https://archive.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
  for i in 1 2 3; do
    wget -c -O "$TARBALL" "$MAIN" || wget -c -O "$TARBALL" "$ARCHIVE" || true
    gzip -t "$TARBALL" 2>/dev/null && break
    echo "Download incomplete, retrying ($i/3)..."
  done
  gzip -t "$TARBALL" 2>/dev/null || { echo "ERROR: Hadoop download failed. Check your internet connection and run this script again."; exit 1; }
  mkdir -p "$HADOOP_HOME"
  tar -xzf "$TARBALL" -C "$HADOOP_HOME" --strip-components=1
else
  echo "Hadoop already installed, skipping."
fi

echo "==> [3/6] Writing Hadoop configuration"
CONF="$HADOOP_HOME/etc/hadoop"
grep -q "^export JAVA_HOME=" "$CONF/hadoop-env.sh" || echo "export JAVA_HOME=$JAVA_HOME" >> "$CONF/hadoop-env.sh"

cat > "$CONF/core-site.xml" << 'EOF'
<configuration>
  <property><name>fs.defaultFS</name><value>hdfs://localhost:9000</value></property>
  <property><name>hadoop.tmp.dir</name><value>/home/${user.name}/hadoop-data</value></property>
</configuration>
EOF

cat > "$CONF/hdfs-site.xml" << 'EOF'
<configuration>
  <property><name>dfs.replication</name><value>1</value></property>
</configuration>
EOF

cat > "$CONF/mapred-site.xml" << 'EOF'
<configuration>
  <property><name>mapreduce.framework.name</name><value>yarn</value></property>
  <property><name>mapreduce.application.classpath</name><value>$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value></property>
</configuration>
EOF

cat > "$CONF/yarn-site.xml" << 'EOF'
<configuration>
  <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
  <property><name>yarn.nodemanager.env-whitelist</name><value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value></property>
</configuration>
EOF

echo "==> [4/6] Setting up passwordless SSH to localhost (Hadoop needs it)"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
grep -qF "$(cat ~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys 2>/dev/null || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
sudo service ssh start
ssh-keyscan -H localhost 0.0.0.0 127.0.0.1 >> ~/.ssh/known_hosts 2>/dev/null || true

if ! grep -q "HADOOP_HOME=" ~/.bashrc; then
cat >> ~/.bashrc << EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
EOF
fi
export JAVA_HOME HADOOP_HOME
export PATH="$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin"

echo "==> [5/6] Formatting HDFS (first time only)"
if [ ! -d "$HOME/hadoop-data/dfs/name" ]; then
  hdfs namenode -format -force
else
  echo "HDFS already formatted, skipping."
fi

echo "==> [6/6] Downloading sample books and building the project"
echo "    The first build downloads many libraries and takes several minutes."
echo "    It looks frozen sometimes. Do NOT press Ctrl+C."
mkdir -p "$PROJECT_DIR/data"
if ! ls "$PROJECT_DIR"/data/*.txt >/dev/null 2>&1; then
  wget -U "Mozilla/5.0" -O "$PROJECT_DIR/data/pride_and_prejudice.txt" https://www.gutenberg.org/cache/epub/1342/pg1342.txt
  wget -U "Mozilla/5.0" -O "$PROJECT_DIR/data/moby_dick.txt" https://www.gutenberg.org/cache/epub/2701/pg2701.txt
  wget -U "Mozilla/5.0" -O "$PROJECT_DIR/data/alice.txt" https://www.gutenberg.org/cache/epub/11/pg11.txt
fi
cd "$PROJECT_DIR"
mvn -B -ntp clean package

echo ""
echo "Setup complete. Next, run:  bash run.sh"