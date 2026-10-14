# deploy_agent_ingabo-sketch

Shell script that deploys, runs, and archives logs for a Student Attendance Tracker. The tracker is a small Python program. This repository does not change how that program works. `deploy_agent.sh` builds the directory layout the program expects, can adjust its alert thresholds, runs a live marking session, and stores the session logs.

**Run-through video:** _record the walkthrough described at the bottom of this file, upload it, and replace this sentence with the URL before you submit._

## What is in the repository

```text
deploy_agent.sh
templates/
├── attendance_checker.py    # interactive marking tool, copied unchanged
├── assets.csv               # 10 students, each with 4 prior sessions
└── config.json              # warning 75, failure 50, total_sessions 5
```

`attendance_checker.py` reads fixed paths relative to the project root:

```text
attendance_tracker_<suffix>/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
└── reports/
```

`reports/` starts empty. The Python program creates `reports/attendance.log` when at least one student is marked present, and `reports/absent.log` when at least one student is marked absent.

## Requirements

- bash
- `python3` (`python3 --version` must succeed)
- `zip` (used only when a deploy is interrupted)

Run the script from the directory where you want the project folder to appear. The templates are always read from the `templates/` folder next to `deploy_agent.sh`, so the script can be started by its full path.

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

## How to select a feature

With no arguments the script opens a menu:

```text
1) Deploy the application
2) Run the application
3) Archive the log files
4) Quit
```

The same three features are available as arguments:

```bash
./deploy_agent.sh deploy
./deploy_agent.sh run
./deploy_agent.sh archive
./deploy_agent.sh help
```

Every prompt uses `read`. A project suffix may contain letters, numbers, `_`, and `-`. The folder name is always `attendance_tracker_<suffix>`. Entering `v1` creates `attendance_tracker_v1`.

## Feature 1: Deploy

Deploy does six things, in this order.

1. **Pre-flight.** It runs `python3 --version` and checks that `zip` is on `PATH`. If either is missing, it stops with an error before creating anything.
2. **Name.** It asks for a suffix and creates `attendance_tracker_<suffix>/Helpers/` and `attendance_tracker_<suffix>/reports/`. If that folder already exists, it asks whether to overwrite it. Answering anything other than `y` or `yes` aborts and leaves the existing folder untouched. If the current directory is not writable, it reports permission denied and stops.
3. **Files.** `attendance_checker.py` is copied unchanged from `templates/`. `config.json` is copied from `templates/` and then, only for a fresh roster, its `total_sessions` number is set to `1`. The roster is built with one of two choices:
   - **A.** Copy students from `templates/assets.csv`. You choose how many (1–10). The header is included. Each sample student already has 4 prior sessions (`Attendance Count + Absence Count = 4`), so `total_sessions` stays **5** (4 prior + today).
   - **B.** Generate a new roster from the name and email arrays in `deploy_agent.sh`. You choose how many (1–20). Both counts start at **0**, so today is session one and `total_sessions` is set to **1**. Only that one number changes. The rest of `config.json` stays in its original order.
4. **Permissions.** `attendance_checker.py` is made executable with `chmod +x` (mode `755` from the usual `644` file). `Helpers/config.json` is restricted with `chmod 600` because it holds the grading thresholds. The script prints `ls -l` for both files and checks those modes.
5. **Thresholds.** Optional. See the next section.
6. **Verify and run.** The script checks that the four required paths exist, that `attendance_checker.py` compiles, and that `config.json` is valid JSON. It prints the roster size, the config values, and the tree. It then runs Feature 2. A successful start is the check that the layout, the roster, and the config work together.

`Ctrl+C` and `Ctrl+Z` are trapped from the start of deploy until this verification finishes. They are turned off before the marking session starts.

## How the threshold update works

After permissions are set, the script asks whether to change the alert thresholds. Pressing Enter keeps the numbers already in the file (75 and 50 unless you chose a fresh roster, which still ships those two defaults).

If you answer `y`:

- Warning is requested with a default of **75**. Failure is requested with a default of **50**. Pressing Enter accepts that default.
- Both values must be whole numbers. Warning must be from 1 to 100. Failure must be from 0 to 100 and must be lower than warning. `abc`, `101`, a blank that does not fall back to a legal default, or a failure greater than or equal to warning is rejected and the question is asked again. `sed` is not called until both numbers are valid.
- `sed` replaces only the number on the `"warning":` line and the number on the `"failure":` line. It does not reformat or reorder the file. `"run_mode"` and `"total_sessions"` are not touched by this step.
- `chmod 600` is applied again so the config file stays owner-read/write only.

Example: warning `90` and failure `40` changes the template from

```json
"warning": 75,
"failure": 50
```

to

```json
"warning": 90,
"failure": 40
```

The script prints the old and new lines so you can see that nothing else moved.

The Python program turns those numbers into a status for today's attendance percentage (`attendance count / total_sessions`):

| Status | Rule |
| --- | --- |
| OK | percentage is at least the warning threshold |
| WARNING | percentage is at least failure and below warning |
| FAILURE | percentage is below failure |

## Feature 2: Run

From the menu, or with `./deploy_agent.sh run`, the script asks which suffix to open and then runs exactly:

```bash
cd attendance_tracker_<suffix>
python3 attendance_checker.py
```

The terminal is handed to the instructor. For each student the program shows the prior counts and waits for `p` (present) or `a` (absent). It updates `Helpers/assets.csv` and writes the session logs under `reports/`. `Ctrl+C` during marking cancels that session, leaves the roster unsaved, and does **not** build the interrupt zip. That zip exists only for an interrupted deploy.

Deploy already calls this feature at the end, so a normal deploy includes a live marking session.

## Feature 3: How log archiving works

Choose menu item 3, or run `./deploy_agent.sh archive`, and enter the project suffix. The script checks the two logs independently. Each log that exists is copied into its own directory. The timestamp is `YYYYMMDD_HHMMSS` from `date`, and both files from the same archive run share that timestamp.

```text
attendance_tracker_<suffix>/
└── archives/
    ├── attendance/
    │   └── attendance_YYYYMMDD_HHMMSS.log
    └── absent/
        └── absent_YYYYMMDD_HHMMSS.log
```

Example:

```text
attendance_tracker_v1/archives/attendance/attendance_20261014_164046.log
attendance_tracker_v1/archives/absent/absent_20261014_164046.log
```

The script prints each source path and the final archive path. The originals in `reports/` stay where they are, so you can archive again later and still inspect the last session.

If a log was never created, the script says so and continues. That happens when nobody was absent (`reports/absent.log` is missing) or nobody was present (`reports/attendance.log` is missing). A missing log is not an error and does not stop the script. If neither log exists, it tells you to run a marking session first and returns without creating archive files.

## How to test Ctrl+C and Ctrl+Z

Start a deploy and answer the questions until the files exist. The clearest moment is the question `Update the alert thresholds?`, because the tree, the copied program, the roster, and `config.json` are already on disk.

Press **Ctrl+C** or **Ctrl+Z**.

The script prints which signal it caught, runs `zip`, and deletes the incomplete folder. It then exits on purpose instead of dropping back to the shell with a half-built directory. A second Ctrl+C during the zip is ignored so the cleanup can finish.

Using suffix `v1` as an example, the archive is:

```text
attendance_tracker_v1_archive.zip
```

It is a real zip file. Unzip it and you get the `attendance_tracker_v1/` tree as it existed at the interrupt: whatever of `attendance_checker.py`, `Helpers/assets.csv`, `Helpers/config.json`, and `reports/` had been created. Later files (for example a finished marking log) are included only if they already existed. The directory `attendance_tracker_v1/` is removed after the zip is written. If `zip` itself fails, the directory is left in place and the script says so.

If you press Ctrl+C before the folder is created (for example on the suffix question, or on the overwrite question), there is nothing to pack. The script says that, and an existing project is not deleted.

Check the result with:

```bash
unzip -l attendance_tracker_v1_archive.zip
unzip -t attendance_tracker_v1_archive.zip
```

## How the deployed structure was tested

These checks were run against this script on macOS with Python 3.14 and `/usr/bin/zip`.

- **Option A, four sample students, default thresholds.** The folder contained `attendance_checker.py`, `Helpers/assets.csv`, `Helpers/config.json`, and an empty `reports/` before marking. Modes were `755` and `600`. `config.json` matched `templates/config.json` byte for byte, and the copied program matched `templates/attendance_checker.py`. Marks were present, absent, present, present. Results were Alice 5/5 = 100% OK, Bob 1/5 = 20% FAILURE, Carol 4/5 = 80% OK, David 3/5 = 60% WARNING. Both logs were written and the roster counts were updated.
- **Archive of that session.** The copies landed in `archives/attendance/attendance_YYYYMMDD_HHMMSS.log` and `archives/absent/absent_YYYYMMDD_HHMMSS.log`. The files in `reports/` were still there afterward.
- **Option B, two new students, both present.** `total_sessions` was 1 and the other config lines stayed at warning 75 and failure 50. Both students were 1/1 = 100% OK. `reports/absent.log` was not created. Archive reported that the absent log was missing, copied only the attendance log, and exited normally.
- **Bad input.** A suffix with a space was rejected. Roster counts `0` and `11` were rejected for a 10-row template. Warning values `abc` and `101` were rejected. Failure equal to warning was rejected. After warning `90` and failure `40`, the deployed `config.json` differed from the template only in those two numbers, and it was still mode `600`.
- **Existing directory.** Refusing to overwrite left the previous `config.json` unchanged. Agreeing to overwrite replaced the tree.
- **Missing tools and permissions.** With `python3` removed from `PATH`, deploy stopped with `python3 is not installed`. With `python3` present and `zip` absent, it stopped with `zip is not installed`. Deploy in a directory without write permission stopped with `permission denied`. A missing project name given to `run` was reported instead of crashing.
- **Ctrl+C before the folder exists.** An existing project was left in place and no zip was written.
- **Ctrl+C and Ctrl+Z at the threshold question.** Each signal wrote `attendance_tracker_<suffix>_archive.zip`, `unzip -t` passed, the listing contained the checker, `Helpers/assets.csv`, `Helpers/config.json`, and `reports/`, and the incomplete directory was gone.
- **Ctrl+C on the first marking prompt.** The program printed that the roster was not changed, no interrupt zip was created, and the project directory remained.

## What the video should show

Record one pass, about five to eight minutes, with the terminal text large enough to read. Talk through the logic while you do it. Use a suffix such as `v1`.

1. Show the repository: `deploy_agent.sh`, `templates/`, and this README. Say that the script is the automation, and the Python file is only copied.
2. Start `./deploy_agent.sh`, choose **1**, suffix `v1`, roster **A**, and copy all **10** students. Say why `total_sessions` stays 5: each sample row already has 4 prior sessions, and today is the fifth.
3. Say yes to the threshold update. Try a bad value such as `abc`, then set warning to `80` and failure to `40`. Point at the `sed` lines and at `chmod 600` in the permission listing.
4. When the checker starts, mark a few students present and absent so the screen shows OK, WARNING, and FAILURE. Quit the menu.
5. Run the script again, choose **3**, and show the two timestamped files under `archives/attendance/` and `archives/absent/`.
6. Start another deploy, suffix `cut`. Answer until you see `Update the alert thresholds?`, then press **Ctrl+C**. Show the message, run `unzip -l attendance_tracker_cut_archive.zip`, and show that `attendance_tracker_cut/` is gone.
7. Repeat once with **Ctrl+Z** on a different suffix, for example `stop`.

Paste the uploaded URL into the video line at the top of this file.
