# Word Count with Hadoop MapReduce

A word count job written in Java, run on a real single-node Hadoop cluster (HDFS and YARN), with a small web app to try it on your own text.

- **The job:** `src/main/java/com/bigdata/wordcount/` holds a Mapper, a Reducer (also used as the Combiner) and a Driver.
- **The live app:** paste text or upload a `.txt` file, and the server uploads it to HDFS and runs the real Hadoop job. You can turn the combiner on or off and compare the job counters.
- **The dashboard:** results of the job on three sample books (Pride and Prejudice, Moby Dick, Alice in Wonderland), including the combiner comparison.

## What you need

- Windows 10 (2004 or later) or Windows 11, with **WSL Ubuntu**. Or any Ubuntu or Debian Linux.
- About 8 GB of RAM and 5 GB of free disk space.
- An internet connection for the first setup.

## Step 0: Install Ubuntu on Windows (skip on Linux)

Open **PowerShell as administrator** and run:

```powershell
wsl --install -d Ubuntu-22.04
```

Restart Windows if it asks. Then open **Ubuntu** from the Start menu and choose a username and password. Run all the following commands inside the Ubuntu window, not PowerShell.

## Step 1: Get the project

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/sampreeth444/wordcount-mapreduce.git wordcount-mapreduce
cd wordcount-mapreduce
```

## Step 2: One-time setup

```bash
bash setup.sh
```

This installs Java, Maven and Hadoop, configures them, downloads the sample books and builds the project. It asks for your Ubuntu password once.

**The first build takes several minutes and can look frozen while it downloads libraries. Wait for it and do not press Ctrl+C.** If a download fails, run `bash setup.sh` again. Finished steps are skipped.

## Step 3: Run

```bash
bash run.sh
```

The first run also runs the job on the sample books, which takes about a minute. When it prints the addresses, open these in your browser:

| Address | What it is |
|---|---|
| http://localhost:8000/live.html | Run the job on your own text |
| http://localhost:8000/dashboard.html | Results on the sample books |
| http://localhost:8088 | Hadoop's job monitor (YARN) |
| http://localhost:9870 | Hadoop's file browser (HDFS) |

Press **Ctrl+C** in the terminal to stop the web app.

## Next time

After a restart of your computer, just open Ubuntu, go to the project folder and run `bash run.sh` again. Do not run `setup.sh` again.

To stop Hadoop completely:

```bash
stop-yarn.sh
stop-dfs.sh
```

## How it works

```
Browser (live.html)
    | click "Run MapReduce"
    v
server.py (Python, localhost:8000)
    | uploads text to HDFS, runs the job
    v
Hadoop: hadoop jar target/wordcount-1.0.jar
    | Map -> Combine -> Shuffle -> Reduce
    v
word counts and job counters back to the page
```

1. **Map:** each line is lowercased, everything that is not a letter is removed, and the mapper emits `(word, 1)` for every word.
2. **Combine:** each mapper adds up its own pairs first, so less data crosses the network. This is the same code as the reducer.
3. **Shuffle:** Hadoop sends all pairs for the same word to the same reducer.
4. **Reduce:** the reducer sums the values for each word and writes `(word, total)` to HDFS.

On the sample books (2.2 MB), the combiner cut the data shuffled to the reducers from 4.36 MB to 0.39 MB, and the output was identical with and without it. The run times (16.3 s with, 20.6 s without) come from one run each, so treat them as indicative.

## Project files

```
setup.sh                  one-time install and build
run.sh                    starts Hadoop and the web app
server.py                 backend: runs jobs and serves the pages
live.html                 the interactive page
dashboard.py              builds dashboard.html from the job output in HDFS
dashboard_template.html   template for the dashboard
metrics.json              measured combiner numbers used by the dashboard
pom.xml                   Maven build file
src/main/java/...         WordCountMapper, WordCountReducer, WordCountDriver
data/                     sample books (downloaded by setup.sh)
```

## Known limitations

- Words are letters only, so "don't" is counted as the two words "don" and "t".
- The Project Gutenberg license text at the start and end of each book is counted too.
- Only one job can run at a time, and the text limit in the live app is 5 MB.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Connection refused` on port 9000 | Hadoop is not running. Run `bash run.sh`. |
| `wsl --install` fails mentioning virtualization | Enable virtualization in the BIOS and try again. |
| Maven seems stuck | Wait. If it truly stalls, press Ctrl+C once, then run `bash setup.sh` again. |
| `localhost:8000` does not load | Make sure `bash run.sh` is still running in the terminal. |
| `Could not resolve host` in WSL | No internet inside WSL. Run `wsl --shutdown` in PowerShell, open Ubuntu again, and retry. |
| Hadoop daemons missing after a restart | Run `bash run.sh`. It starts SSH and the daemons. |