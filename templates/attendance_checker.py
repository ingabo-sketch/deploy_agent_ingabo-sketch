#!/usr/bin/env python3
"""Interactive student attendance tracker.

The script looks for its inputs at fixed paths relative to the project root
(the directory that contains this file):

    Helpers/assets.csv
    Helpers/config.json
    reports/

Run it from the project root:

    python3 attendance_checker.py

The instructor marks each student present or absent. Counts in the roster are
updated, and this session is written under reports/. attendance.log is created
only when at least one student is present. absent.log is created only when at
least one student is absent.
"""

import csv
import json
import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))
ROSTER_PATH = os.path.join(ROOT, "Helpers", "assets.csv")
CONFIG_PATH = os.path.join(ROOT, "Helpers", "config.json")
REPORTS_DIR = os.path.join(ROOT, "reports")
ATTENDANCE_LOG = os.path.join(REPORTS_DIR, "attendance.log")
ABSENT_LOG = os.path.join(REPORTS_DIR, "absent.log")

HEADER = ["Email", "Names", "Attendance Count", "Absence Count"]


def fail(message):
    print("Error: {0}".format(message), file=sys.stderr)
    sys.exit(1)


def load_config():
    if not os.path.isfile(CONFIG_PATH):
        fail("missing {0}".format(CONFIG_PATH))
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        fail("could not read config.json ({0})".format(exc))

    try:
        warning = int(config["thresholds"]["warning"])
        failure = int(config["thresholds"]["failure"])
        total_sessions = int(config["total_sessions"])
        run_mode = str(config["run_mode"])
    except (KeyError, TypeError, ValueError):
        fail("config.json must contain thresholds.warning, thresholds.failure, run_mode, and total_sessions")

    if total_sessions < 1:
        fail("total_sessions must be at least 1")
    return warning, failure, total_sessions, run_mode


def load_roster():
    if not os.path.isfile(ROSTER_PATH):
        fail("missing {0}".format(ROSTER_PATH))
    students = []
    try:
        with open(ROSTER_PATH, "r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != HEADER:
                fail("assets.csv header must be: {0}".format(",".join(HEADER)))
            for row in reader:
                students.append(
                    {
                        "email": row["Email"].strip(),
                        "name": row["Names"].strip(),
                        "attendance": int(row["Attendance Count"]),
                        "absence": int(row["Absence Count"]),
                    }
                )
    except (OSError, KeyError, ValueError) as exc:
        fail("could not read assets.csv ({0})".format(exc))
    if not students:
        fail("assets.csv has no students")
    return students


def status_for(rate, warning, failure):
    if rate < failure:
        return "FAILURE"
    if rate < warning:
        return "WARNING"
    return "OK"


def ask_mark(student, index, total):
    prior = student["attendance"] + student["absence"]
    while True:
        print("")
        print("[{0}/{1}] {2} <{3}>".format(index, total, student["name"], student["email"]))
        print("  Prior sessions recorded: {0} (present {1}, absent {2})".format(
            prior, student["attendance"], student["absence"]
        ))
        try:
            answer = input("  Mark [p]resent or [a]bsent: ").strip().lower()
        except EOFError:
            fail("input closed before the roster was finished")
        if answer in ("p", "present"):
            return True
        if answer in ("a", "absent"):
            return False
        print("  Enter p or a.")


def save_roster(students):
    with open(ROSTER_PATH, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(HEADER)
        for student in students:
            writer.writerow(
                [
                    student["email"],
                    student["name"],
                    student["attendance"],
                    student["absence"],
                ]
            )


def write_log(path, title, students, warning, failure, total_sessions, run_mode):
    stamp = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    lines = [
        title,
        "timestamp: {0}".format(stamp),
        "run_mode: {0}".format(run_mode),
        "total_sessions: {0}".format(total_sessions),
        "warning: {0}".format(warning),
        "failure: {0}".format(failure),
        "",
        "email,name,attendance_count,absence_count,attendance_percent,status",
    ]
    for student in students:
        lines.append(
            "{email},{name},{attendance},{absence},{rate:.1f},{status}".format(**student)
        )
    lines.append("")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def main():
    if not os.path.isdir(REPORTS_DIR):
        fail("missing {0} — the project layout is incomplete".format(REPORTS_DIR))
    if not os.path.isdir(os.path.join(ROOT, "Helpers")):
        fail("missing Helpers/ — the project layout is incomplete")

    warning, failure, total_sessions, run_mode = load_config()
    students = load_roster()

    print("Student Attendance Tracker")
    print("Project root: {0}".format(ROOT))
    print("Run mode: {0}".format(run_mode))
    print("Total sessions including today: {0}".format(total_sessions))
    print("Alert thresholds: warning {0}%, failure {1}%".format(warning, failure))
    print("Students on this roster: {0}".format(len(students)))

    mismatched = [
        student["name"]
        for student in students
        if student["attendance"] + student["absence"] != total_sessions - 1
    ]
    if mismatched:
        print("")
        print("Warning: prior sessions for these students do not equal total_sessions - 1:")
        for name in mismatched:
            print("  - {0}".format(name))
        print("total_sessions should be one more than the prior sessions stored in the roster.")

    present_rows = []
    absent_rows = []

    try:
        for index, student in enumerate(students, start=1):
            is_present = ask_mark(student, index, len(students))
            if is_present:
                student["attendance"] += 1
                mark_label = "PRESENT"
            else:
                student["absence"] += 1
                mark_label = "ABSENT"

            rate = (student["attendance"] / total_sessions) * 100
            status = status_for(rate, warning, failure)
            student["rate"] = rate
            student["status"] = status
            print(
                "  {0} marked {1}. Attendance {2}/{3} ({4:.1f}%). Status: {5}".format(
                    student["name"],
                    mark_label,
                    student["attendance"],
                    total_sessions,
                    rate,
                    status,
                )
            )
            if is_present:
                present_rows.append(student)
            else:
                absent_rows.append(student)
    except KeyboardInterrupt:
        print("")
        print("Marking cancelled. The roster and logs were not changed.")
        sys.exit(130)

    save_roster(students)
    print("")
    print("Roster updated: Helpers/assets.csv")

    if present_rows:
        write_log(
            ATTENDANCE_LOG,
            "attendance log",
            present_rows,
            warning,
            failure,
            total_sessions,
            run_mode,
        )
        print("Wrote {0}".format(ATTENDANCE_LOG))
    else:
        print("Nobody was present, so reports/attendance.log was not created.")

    if absent_rows:
        write_log(
            ABSENT_LOG,
            "absent log",
            absent_rows,
            warning,
            failure,
            total_sessions,
            run_mode,
        )
        print("Wrote {0}".format(ABSENT_LOG))
    else:
        print("Nobody was absent, so reports/absent.log was not created.")

    print("")
    print("Session complete.")


if __name__ == "__main__":
    main()
