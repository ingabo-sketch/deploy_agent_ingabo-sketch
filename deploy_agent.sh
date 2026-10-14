#!/usr/bin/env bash
#
# deploy_agent.sh
# Deploy, run, and archive logs for the Student Attendance Tracker.
#
# Feature 1 (deploy)  creates attendance_tracker_<name>/ from templates/.
# Feature 2 (run)     executes python3 attendance_checker.py in that project.
# Feature 3 (archive) copies session logs into timestamped archive folders.
#
# Ctrl+C (SIGINT) and Ctrl+Z (SIGTSTP) are trapped only while a deploy is
# being created. They zip whatever exists so far and remove that directory.
# They are not trapped while a marking session is running.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
TEMPLATE_APP="${TEMPLATE_DIR}/attendance_checker.py"
TEMPLATE_ASSETS="${TEMPLATE_DIR}/assets.csv"
TEMPLATE_CONFIG="${TEMPLATE_DIR}/config.json"

PROJECT_DIR=""
TREE_CREATED=0
ANSWER=""

# Option B builds rows from these arrays. Counts are written as 0, 0.
SAMPLE_NAMES=(
  "Alice Johnson"
  "Bob Smith"
  "Carol White"
  "David Brown"
)
SAMPLE_EMAILS=(
  "alice@example.com"
  "bob@example.com"
  "carol@example.com"
  "david@example.com"
)

usage() {
  cat <<EOF
Usage: ./deploy_agent.sh [deploy|run|archive|help]

With no argument, an interactive menu is shown.

  deploy     Create attendance_tracker_<name>/ and then run the app
  run        Run python3 attendance_checker.py in an existing project
  archive    Copy reports/attendance.log and reports/absent.log into
             archives/attendance/ and archives/absent/ with a timestamp
  help       Show this message

The project folder is attendance_tracker_<suffix>/ in the current directory.
Suffix v1 creates attendance_tracker_v1/.

Ctrl+C or Ctrl+Z during deploy packs that folder into
attendance_tracker_<suffix>_archive.zip and then removes the folder.
That trap is not active while a marking session is running.

Run this script from the directory where the project folder should be created.
Templates are read from ${TEMPLATE_DIR}.
EOF
}

prompt() {
  local text="$1"
  # Print the prompt ourselves so it is shown in a terminal session.
  # read -p hides the prompt when stdin is not a terminal.
  printf '%s' "$text" >&2
  if ! read -r ANSWER; then
    echo ""
    echo "Error: no input available." >&2
    return 1
  fi
  ANSWER="$(printf '%s' "$ANSWER" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  return 0
}

is_whole_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is not installed. Install Python 3 and run this script again." >&2
    return 1
  fi
  local version
  if ! version="$(python3 --version 2>&1)"; then
    echo "Error: python3 --version failed. Python 3 is not usable on this machine." >&2
    return 1
  fi
  echo "Pre-flight: ${version}"
}

require_zip() {
  if ! command -v zip >/dev/null 2>&1; then
    echo "Error: zip is not installed. Install zip and run this script again." >&2
    return 1
  fi
  echo "Pre-flight: zip found at $(command -v zip)"
}

require_templates() {
  local missing=0
  local path
  for path in "$TEMPLATE_APP" "$TEMPLATE_ASSETS" "$TEMPLATE_CONFIG"; do
    if [[ ! -f "$path" ]]; then
      echo "Error: missing template ${path}" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

safe_project_dir() {
  [[ "$PROJECT_DIR" =~ ^attendance_tracker_[A-Za-z0-9_-]+$ ]]
}

on_deploy_interrupt() {
  local signal_name="$1"
  local how=""
  local archive=""

  # Ignore a second Ctrl+C/Ctrl+Z while the incomplete tree is being packed.
  trap '' INT TSTP

  case "$signal_name" in
    SIGINT) how="Ctrl+C" ;;
    SIGTSTP) how="Ctrl+Z" ;;
    *) how="$signal_name" ;;
  esac

  echo ""
  echo "============================================================"
  echo "Deployment interrupted by ${signal_name} (${how})."
  echo "============================================================"

  if [[ "$TREE_CREATED" == "1" && -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]] && safe_project_dir; then
    archive="${PROJECT_DIR}_archive.zip"
    echo "Packing the incomplete project into ${archive}."
    echo "The zip will contain whatever of ${PROJECT_DIR}/ exists right now."
    rm -f "$archive"
    if zip -r "$archive" "$PROJECT_DIR"; then
      rm -rf "$PROJECT_DIR"
      echo ""
      echo "Archive written: ${archive}"
      echo "Removed incomplete directory: ${PROJECT_DIR}"
      echo "Session closed. No half-made project directory was left behind."
    else
      echo "Error: zip failed. The incomplete directory was left in place: ${PROJECT_DIR}" >&2
      exit 1
    fi
  else
    echo "No project directory had been created yet, so nothing was archived or deleted."
  fi
  exit 0
}

enable_deploy_traps() {
  trap 'on_deploy_interrupt SIGINT' INT
  trap 'on_deploy_interrupt SIGTSTP' TSTP
}

disable_deploy_traps() {
  trap - INT TSTP
}

ask_project_suffix() {
  local suffix=""
  echo ""
  echo "The project folder will be named attendance_tracker_<suffix>."
  echo "Use letters, numbers, underscore, or hyphen."
  while true; do
    prompt "Project suffix: " || return 1
    suffix="$ANSWER"
    if [[ ! "$suffix" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "Error: the suffix must contain only letters, numbers, underscore, or hyphen."
      continue
    fi
    PROJECT_DIR="attendance_tracker_${suffix}"
    if [[ -d "$PROJECT_DIR" ]]; then
      echo "Error: ${PROJECT_DIR} already exists."
      prompt "Overwrite it? This deletes the existing directory. [y/N]: " || return 1
      case "$ANSWER" in
        y|Y|yes|YES)
          echo "The existing directory will be replaced."
          return 0
          ;;
        *)
          echo "Error: aborted. ${PROJECT_DIR} was left unchanged." >&2
          PROJECT_DIR=""
          return 1
          ;;
      esac
    fi
    return 0
  done
}

ask_existing_project() {
  local suffix=""
  echo ""
  echo "Which deployed project should be used?"
  while true; do
    prompt "Project suffix (folder attendance_tracker_<suffix>): " || return 1
    suffix="$ANSWER"
    if [[ ! "$suffix" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "Error: the suffix must contain only letters, numbers, underscore, or hyphen."
      continue
    fi
    PROJECT_DIR="attendance_tracker_${suffix}"
    if [[ ! -d "$PROJECT_DIR" ]]; then
      echo "Error: ${PROJECT_DIR} does not exist. Deploy it first, or enter a different suffix."
      continue
    fi
    return 0
  done
}

copy_roster_from_template() {
  local dest="$1"
  local available count
  available="$(tail -n +2 "$TEMPLATE_ASSETS" | wc -l | tr -d '[:space:]')"
  echo ""
  echo "Option A copies students from templates/assets.csv."
  echo "The sample roster has ${available} students, each with 4 prior sessions."
  while true; do
    prompt "How many students should be copied? [1-${available}]: " || return 1
    count="$ANSWER"
    if ! is_whole_number "$count" || [[ "$count" -lt 1 || "$count" -gt "$available" ]]; then
      echo "Error: enter a whole number from 1 to ${available}."
      continue
    fi
    # NR 1 is the header. Data rows are 2 .. count+1. awk avoids a SIGPIPE from head.
    awk -v count="$count" 'NR == 1 || NR <= count + 1' "$TEMPLATE_ASSETS" > "$dest"
    echo "Copied ${count} student rows plus the header into Helpers/assets.csv."
    echo "Those rows carry 4 prior sessions, so total_sessions stays 5 (4 prior + today)."
    return 0
  done
}

generate_roster() {
  local dest="$1"
  local max="${#SAMPLE_NAMES[@]}"
  local count i name email
  echo ""
  echo "Option B builds a fresh roster from the script's name and email arrays."
  echo "Attendance Count and Absence Count start at 0. This is session one."
  while true; do
    prompt "How many students should be generated? [1-${max}]: " || return 1
    count="$ANSWER"
    if ! is_whole_number "$count" || [[ "$count" -lt 1 || "$count" -gt "$max" ]]; then
      echo "Error: enter a whole number from 1 to ${max}."
      continue
    fi
    {
      echo "Email,Names,Attendance Count,Absence Count"
      for ((i = 0; i < count; i++)); do
        name="${SAMPLE_NAMES[$i]}"
        email="${SAMPLE_EMAILS[$i]}"
        printf '%s,%s,0,0\n' "$email" "$name"
      done
    } > "$dest"
    echo "Wrote ${count} new student rows with attendance 0 and absence 0."
    return 0
  done
}

set_total_sessions() {
  local config="$1"
  local value="$2"
  local tmp
  if ! grep -Eq '"total_sessions":[[:space:]]*[0-9]+' "$config"; then
    echo "Error: config.json has no total_sessions line to update." >&2
    return 1
  fi
  tmp="$(mktemp)"
  sed -E "s/(\"total_sessions\":[[:space:]]*)[0-9]+/\\1${value}/" "$config" > "$tmp"
  cat "$tmp" > "$config"
  rm -f "$tmp"
  echo "Shipped total_sessions: ${value} so the config matches this roster."
}

populate_project() {
  local choice dest config
  dest="${PROJECT_DIR}/Helpers/assets.csv"
  config="${PROJECT_DIR}/Helpers/config.json"

  cp "$TEMPLATE_APP" "${PROJECT_DIR}/attendance_checker.py" || {
    echo "Error: could not copy attendance_checker.py. Permission denied?" >&2
    return 1
  }
  cp "$TEMPLATE_CONFIG" "$config" || {
    echo "Error: could not copy config.json. Permission denied?" >&2
    return 1
  }

  echo ""
  echo "attendance_checker.py and config.json were copied unchanged from templates/."
  echo "How should Helpers/assets.csv be built?"
  echo "  A) Copy students from templates/assets.csv"
  echo "  B) Generate a fresh roster (counts start at 0)"
  while true; do
    prompt "Roster choice [A/B]: " || return 1
    choice="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]')"
    case "$choice" in
      a)
        copy_roster_from_template "$dest" || return 1
        echo "config.json was left unchanged. total_sessions remains 5."
        return 0
        ;;
      b)
        generate_roster "$dest" || return 1
        # A fresh roster has 0 prior sessions, so today is session 1.
        # Only the total_sessions number is changed. The rest of the file stays put.
        set_total_sessions "$config" 1 || return 1
        return 0
        ;;
      *)
        echo "Error: enter A or B."
        ;;
    esac
  done
}

set_permissions() {
  local app="${PROJECT_DIR}/attendance_checker.py"
  local config="${PROJECT_DIR}/Helpers/config.json"

  chmod +x "$app" || {
    echo "Error: chmod +x failed for attendance_checker.py. Permission denied?" >&2
    return 1
  }
  chmod 600 "$config" || {
    echo "Error: chmod 600 failed for Helpers/config.json. Permission denied?" >&2
    return 1
  }

  echo ""
  echo "Permissions set:"
  ls -l "$app"
  ls -l "$config"
}

update_thresholds() {
  local config="${PROJECT_DIR}/Helpers/config.json"
  local warning="" failure="" tmp before_warning before_failure

  echo ""
  echo "Alert thresholds live in Helpers/config.json."
  echo "warning is the attendance percentage that raises a warning. Default: 75."
  echo "failure is the attendance percentage that counts as failing. Default: 50."
  prompt "Update the alert thresholds? [y/N]: " || return 1
  case "$ANSWER" in
    y|Y|yes|YES) ;;
    *)
      echo "Keeping the thresholds already in config.json."
      return 0
      ;;
  esac

  while true; do
    prompt "Warning percentage [75]: " || return 1
    warning="${ANSWER:-75}"
    if ! is_whole_number "$warning" || [[ "$warning" -lt 1 || "$warning" -gt 100 ]]; then
      echo "Error: warning must be a whole number from 1 to 100."
      continue
    fi
    break
  done

  while true; do
    prompt "Failure percentage [50]: " || return 1
    failure="${ANSWER:-50}"
    if ! is_whole_number "$failure" || [[ "$failure" -gt 100 ]]; then
      echo "Error: failure must be a whole number from 0 to 100."
      continue
    fi
    if [[ "$failure" -ge "$warning" ]]; then
      echo "Error: failure (${failure}) must be lower than warning (${warning})."
      continue
    fi
    break
  done

  if ! grep -Eq '"warning":[[:space:]]*[0-9]+' "$config"; then
    echo "Error: config.json has no \"warning\" line. Refusing to edit it." >&2
    return 1
  fi
  if ! grep -Eq '"failure":[[:space:]]*[0-9]+' "$config"; then
    echo "Error: config.json has no \"failure\" line. Refusing to edit it." >&2
    return 1
  fi

  before_warning="$(grep -E '"warning":[[:space:]]*[0-9]+' "$config")"
  before_failure="$(grep -E '"failure":[[:space:]]*[0-9]+' "$config")"

  tmp="$(mktemp)"
  # Targeted substitutions only. The rest of the file, including order, is unchanged.
  sed -E \
    -e "s/(\"warning\":[[:space:]]*)[0-9]+/\\1${warning}/" \
    -e "s/(\"failure\":[[:space:]]*)[0-9]+/\\1${failure}/" \
    "$config" > "$tmp" || {
      rm -f "$tmp"
      echo "Error: sed could not update config.json." >&2
      return 1
    }
  cat "$tmp" > "$config"
  rm -f "$tmp"
  chmod 600 "$config" || {
    echo "Error: could not restore mode 600 on config.json after the update." >&2
    return 1
  }

  echo "sed updated only the threshold numbers:"
  echo "  warning: ${before_warning}  ->  $(grep -E '"warning":[[:space:]]*[0-9]+' "$config")"
  echo "  failure: ${before_failure}  ->  $(grep -E '"failure":[[:space:]]*[0-9]+' "$config")"
  ls -l "$config"
}

verify_deployment() {
  local app="${PROJECT_DIR}/attendance_checker.py"
  local config="${PROJECT_DIR}/Helpers/config.json"
  local roster="${PROJECT_DIR}/Helpers/assets.csv"
  local reports="${PROJECT_DIR}/reports"
  local students

  echo ""
  echo "Deployment check for ${PROJECT_DIR}:"
  local required
  for required in "$app" "$config" "$roster" "$reports"; do
    if [[ ! -e "$required" ]]; then
      echo "Error: missing ${required}" >&2
      return 1
    fi
    echo "  found ${required}"
  done
  if [[ ! -d "$reports" || ! -d "${PROJECT_DIR}/Helpers" ]]; then
    echo "Error: Helpers/ or reports/ is not a directory." >&2
    return 1
  fi

  students="$(tail -n +2 "$roster" | wc -l | tr -d '[:space:]')"
  echo "  roster students: ${students}"
  echo "  config:"
  grep -E '"warning"|"failure"|"run_mode"|"total_sessions"' "$config" | sed 's/^/    /'
  echo "  layout:"
  (cd "$PROJECT_DIR" && find . | sort | sed 's/^/    /')

  echo ""
  echo "Structure, roster, and config are in place. Starting the application."
}

create_tree() {
  if ! safe_project_dir; then
    echo "Error: refusing to create an unexpected path: ${PROJECT_DIR}" >&2
    return 1
  fi
  # Set this before any delete so an interrupt mid-create still cleans up.
  TREE_CREATED=1
  if [[ -d "$PROJECT_DIR" ]]; then
    rm -rf "$PROJECT_DIR" || {
      echo "Error: could not replace ${PROJECT_DIR}. Permission denied?" >&2
      return 1
    }
  fi
  mkdir -p "${PROJECT_DIR}/Helpers" "${PROJECT_DIR}/reports" || {
    echo "Error: could not create ${PROJECT_DIR}. Permission denied for $(pwd)?" >&2
    return 1
  }
  echo "Created ${PROJECT_DIR}/ with Helpers/ and an empty reports/."
}

deploy_body() {
  PROJECT_DIR=""
  TREE_CREATED=0

  echo ""
  echo "Feature 1: Deploy the application"
  require_python3 || return 1
  require_zip || return 1
  require_templates || return 1

  if [[ ! -w "." ]]; then
    echo "Error: permission denied. Cannot create a project in $(pwd)." >&2
    return 1
  fi

  ask_project_suffix || return 1
  # Traps are already on. The directory is created only after the name is accepted,
  # so Ctrl+C on the name prompt does not delete an existing project.
  create_tree || return 1
  populate_project || return 1
  set_permissions || return 1
  update_thresholds || return 1
  verify_deployment || return 1
}

run_application() {
  local target="$1"
  local status=0

  if [[ ! -d "$target" ]]; then
    echo "Error: ${target} does not exist. Deploy it first." >&2
    return 1
  fi
  if [[ ! -f "${target}/attendance_checker.py" ]]; then
    echo "Error: ${target}/attendance_checker.py is missing." >&2
    return 1
  fi

  echo ""
  echo "Feature 2: Run the application"
  echo "cd ${target}"
  echo "python3 attendance_checker.py"
  echo ""
  echo "The terminal now belongs to the instructor for this marking session."
  echo "Ctrl+C during marking cancels the session. It does not zip the project."
  echo ""

  # Not the deploy trap. This only lets the script continue after Python
  # handles Ctrl+C. It does not archive anything.
  trap 'true' INT
  (
    cd "$target" || exit 1
    python3 attendance_checker.py
  )
  status=$?
  trap - INT

  echo ""
  if [[ "$status" -eq 0 ]]; then
    echo "Marking session finished."
  else
    echo "Marking session ended with status ${status}."
  fi
  return "$status"
}

archive_logs() {
  local reports attendance absent stamp attendance_dest absent_dest archived=0

  echo ""
  echo "Feature 3: Archive the log files"
  reports="${PROJECT_DIR}/reports"
  attendance="${reports}/attendance.log"
  absent="${reports}/absent.log"

  if [[ ! -d "$reports" ]]; then
    echo "Error: ${reports} does not exist. Deploy the project and run a session first." >&2
    return 1
  fi

  stamp="$(date +%Y%m%d_%H%M%S)"
  echo "Timestamp for this archive: ${stamp}"

  if [[ -f "$attendance" ]]; then
    attendance_dest="${PROJECT_DIR}/archives/attendance/attendance_${stamp}.log"
    mkdir -p "${PROJECT_DIR}/archives/attendance" || {
      echo "Error: could not create archives/attendance. Permission denied?" >&2
      return 1
    }
    cp "$attendance" "$attendance_dest" || {
      echo "Error: could not archive ${attendance}." >&2
      return 1
    }
    echo "Archived attendance log:"
    echo "  from ${attendance}"
    echo "  to   ${attendance_dest}"
    archived=1
  else
    echo "reports/attendance.log does not exist (nobody was marked present). Skipped."
  fi

  if [[ -f "$absent" ]]; then
    absent_dest="${PROJECT_DIR}/archives/absent/absent_${stamp}.log"
    mkdir -p "${PROJECT_DIR}/archives/absent" || {
      echo "Error: could not create archives/absent. Permission denied?" >&2
      return 1
    }
    cp "$absent" "$absent_dest" || {
      echo "Error: could not archive ${absent}." >&2
      return 1
    }
    echo "Archived absent log:"
    echo "  from ${absent}"
    echo "  to   ${absent_dest}"
    archived=1
  else
    echo "reports/absent.log does not exist (nobody was marked absent). Skipped."
  fi

  if [[ "$archived" -eq 0 ]]; then
    echo "No session logs were found under ${reports}."
    echo "Run the application and mark the roster, then archive again."
    return 0
  fi
  echo "Archive complete. The original files in reports/ were left in place."
}

deploy() {
  enable_deploy_traps
  if ! deploy_body; then
    disable_deploy_traps
    return 1
  fi
  # The signal trap covers creation and setup only, not the marking session.
  disable_deploy_traps
  run_application "$PROJECT_DIR"
}

run_feature() {
  require_python3 || return 1
  ask_existing_project || return 1
  run_application "$PROJECT_DIR"
}

archive_feature() {
  ask_existing_project || return 1
  archive_logs
}

print_menu() {
  echo ""
  echo "Student Attendance Tracker"
  echo "  1) Deploy the application"
  echo "  2) Run the application"
  echo "  3) Archive the log files"
  echo "  4) Quit"
}

menu() {
  local choice
  while true; do
    print_menu
    prompt "Select a feature [1-4]: " || exit 1
    choice="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]')"
    case "$choice" in
      1|deploy)
        deploy || true
        ;;
      2|run)
        run_feature || true
        ;;
      3|archive)
        archive_feature || true
        ;;
      4|q|quit|exit)
        echo "Goodbye."
        exit 0
        ;;
      *)
        echo "Enter 1, 2, 3, or 4."
        ;;
    esac
  done
}

main() {
  case "${1:-}" in
    "" )
      menu
      ;;
    deploy)
      deploy
      ;;
    run)
      run_feature
      ;;
    archive)
      archive_feature
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
