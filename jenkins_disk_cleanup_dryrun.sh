#!/bin/bash

################################################################################
# Jenkins Disk Cleanup - DRY RUN / PRE-FLIGHT CHECK
# Date: January 22, 2026
# Purpose: Safely analyze what WOULD be cleaned without making any changes
# This script is READ-ONLY and will NOT delete anything
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
log_info()      { echo -e "${BLUE}[INFO]${NC} $1" }
log_success()   { echo -e "${GREEN}[SAFE]${NC} $1" }
log_warning()   { echo -e "${YELLOW}[WARNING]${NC} $1" }
log_error()     { echo -e "${RED}[DANGER]${NC} $1" }
log_plan() { echo -e "${CYAN}[PLAN]${NC} $1" }
log_critical() { echo -e "${MAGENTA}[CRITICAL - DO NOT DELETE]${NC} $1" }

# Cleanup candidates output helpers (for GitHub Actions parsing)
init_cleanup_candidates() {
    local candidates_dir
    candidates_dir="$(dirname "$CLEANUP_CANDIDATES_FILE")"
    mkdir -p "$candidates_dir" 2>/dev/null || true

    if ! : > "$CLEANUP_CANDIDATES_FILE" 2>/dev/null; then
        log_warning "Cannot write to candidates file: $CLEANUP_CANDIDATES_FILE"
        CLEANUP_CANDIDATES_FILE="$(mktemp /tmp/jenkins_cleanup_candidates.XXXXXX)"
        log_info "Falling back to writable candidates file: $CLEANUP_CANDIDATES_FILE"
        : > "$CLEANUP_CANDIDATES_FILE"
    fi
}

emit_cleanup_candidates() {
    local total emitted truncated

    if [[ -f "$CLEANUP_CANDIDATES_FILE" ]]; then
        total=$(wc -l < "$CLEANUP_CANDIDATES_FILE" | tr -d ' ')
    else
        total="0"
    fi

    if [[ "${CLEANUP_CANDIDATES_MAX}" -eq 0 ]]; then
        emitted="$total"
        truncated="false"
    else
        if [[ "$total" -gt "${CLEANUP_CANDIDATES_MAX}" ]]; then
            truncated="true"
            emitted="${CLEANUP_CANDIDATES_MAX}"
        else
            truncated="false"
            emitted="$total"
        fi
    fi

    echo "CLEANUP_CANDIDATES_TOTAL=${total}"
    echo "CLEANUP_CANDIDATES_MAX=${CLEANUP_CANDIDATES_MAX}"
    echo "CLEANUP_CANDIDATES_EMITTED=${emitted}"
    echo "CLEANUP_CANDIDATES_TRUNCATED=${truncated}"
    echo "CLEANUP_CANDIDATES_FILE=${CLEANUP_CANDIDATES_FILE}"
    echo "CLEANUP_CANDIDATES_BEGIN"
    if [[ -f "$CLEANUP_CANDIDATES_FILE" ]]; then
        if [[ "${CLEANUP_CANDIDATES_MAX}" -eq 0 ]]; then
            cat "$CLEANUP_CANDIDATES_FILE"
        else
            head -n "${CLEANUP_CANDIDATES_MAX}" "$CLEANUP_CANDIDATES_FILE"
        fi
    fi
    echo "CLEANUP_CANDIDATES_END"
}

# Function to get disk usage
get_disk_usage() { df -h / | tail -1 | awk '{print $5}' }

# Function to get disk usage as integer percent (no % sign)
get_disk_usage_pct() { df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}' }

# Function to calculate directory size
get_dir_size() { du -sh "$1" 2>/dev/null | cut -f1 || echo "0B" }

# Function to calculate directory size in bytes for comparison
get_dir_size_bytes() { du -sb "$1" 2>/dev/null | cut -f1 || echo "0" }

add_candidate() {
  # TYPE<TAB>PATH
  local typ="$1"; shift
  local path="$1"; shift || true
  [[ -z "${typ:-}" || -z "${path:-}" ]] && return 0
  printf "%s\t%s\n" "$typ" "$path" >> "$CLEANUP_CANDIDATES_FILE"
}

# Function to format bytes to human-readable (best effort)
format_bytes() {
    local bytes="${1:-0}"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$bytes"
    else
        echo "${bytes}B"
    fi
}

# --- best-effort bytes for file/dir ---
path_bytes() {
  local p="$1"
  if [[ -e "$p" ]]; then
    du -sb "$p" 2>/dev/null | awk '{print $1}' || echo "0"
  else
    echo "0"
  fi
}

# --- accumulate per-step metrics ---
STEP_NAMES=()
STEP_USED_BYTES=()
STEP_RECLAIM_BYTES=()
STEP_NOTES=()

add_step_metric() {
  # add_step_metric "Step name" used_bytes reclaim_bytes "notes"
  STEP_NAMES+=("$1")
  STEP_USED_BYTES+=("${2:-0}")
  STEP_RECLAIM_BYTES+=("${3:-0}")
  STEP_NOTES+=("${4:-}")
}

print_step_metrics() {
  echo ""
  log_info "PER-STEP DISK ESTIMATES (USED vs POTENTIAL RECLAIM)"
  echo "----------------------------------------------------------------"
  printf "%-32s %-14s %-14s %s\n" "STEP" "USED" "RECLAIM" "NOTES"
  echo "----------------------------------------------------------------"
  local i
  for i in "${!STEP_NAMES[@]}"; do
    printf "%-32s %-14s %-14s %s\n" \
      "${STEP_NAMES[$i]}" \
      "$(format_bytes "${STEP_USED_BYTES[$i]}")" \
      "$(format_bytes "${STEP_RECLAIM_BYTES[$i]}")" \
      "${STEP_NOTES[$i]}"
  done
  echo "----------------------------------------------------------------"
  local total_used=0 total_reclaim=0
  for i in "${!STEP_NAMES[@]}"; do
    total_used=$((total_used + STEP_USED_BYTES[$i]))
    total_reclaim=$((total_reclaim + STEP_RECLAIM_BYTES[$i]))
  done
  printf "%-32s %-14s %-14s %s\n" "TOTAL (steps tracked)" "$(format_bytes "$total_used")" "$(format_bytes "$total_reclaim")" ""
  echo ""
}

# --- candidates-by-type reclaim breakdown ---
print_candidate_reclaim_by_type() {
  [[ ! -f "$CLEANUP_CANDIDATES_FILE" ]] && return 0
  echo ""
  log_info "RECLAIM ESTIMATE BY CANDIDATE TYPE"
  echo "----------------------------------------------------------------"
  declare -A TYPE_BYTES=()
  while IFS=$'\t' read -r typ path || [[ -n "${typ:-}" ]]; do
    [[ -z "${typ:-}" || -z "${path:-}" ]] && continue
    b="$(path_bytes "$path")"
    TYPE_BYTES["$typ"]=$(( ${TYPE_BYTES["$typ"]:-0} + b ))
  done < "$CLEANUP_CANDIDATES_FILE"

  for t in "${!TYPE_BYTES[@]}"; do
    printf "%-18s %s\n" "$t" "$(format_bytes "${TYPE_BYTES[$t]}")"
  done | sort -hr -k2,2
  echo "----------------------------------------------------------------"
}

# Function to count items
count_items() {
    find "$1" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' '
}

JENKINS_HOME="/var/lib/jenkins"
DISK_USAGE_THRESHOLD_PCT="${DISK_USAGE_THRESHOLD_PCT:-30}"
TOP_BUILDS_TOTAL_BYTES=0
TOP_BUILDS_COUNT=0
OLD_LARGE_TOTAL_BYTES=0
OLD_LARGE_COUNT=0
CLEANUP_CANDIDATES_FILE="${CLEANUP_CANDIDATES_FILE:-/tmp/jenkins_cleanup_candidates.txt}"
CLEANUP_CANDIDATES_MAX="${CLEANUP_CANDIDATES_MAX:-500}"
TOP_HEAVIEST_CANDIDATES="${TOP_HEAVIEST_CANDIDATES:-50}"

init_cleanup_candidates

################################################################################
# Pre-flight checks
################################################################################

echo "================================================================================"
echo "              JENKINS DISK CLEANUP - DRY RUN (NO CHANGES MADE)"
echo "================================================================================"
echo ""
log_warning "This is a READ-ONLY analysis. Nothing will be deleted."
echo ""

DISK_USAGE_RAW="$(get_disk_usage || true)"
DISK_USAGE_PCT="$(get_disk_usage_pct 2>/dev/null || echo "0")"
if [[ -z "${DISK_USAGE_PCT}" ]]; then DISK_USAGE_PCT="0"; fi

log_info "Current disk usage: ${DISK_USAGE_RAW} (threshold: ${DISK_USAGE_THRESHOLD_PCT}%)"
log_info "Current date/time: $(date)"
echo ""

# Machine-readable outputs (useful for GitHub Actions parsing)
if [[ "${DISK_USAGE_PCT}" -ge "${DISK_USAGE_THRESHOLD_PCT}" ]]; then
    DISK_CLEANUP_SHOULD_RUN="true"
else
    DISK_CLEANUP_SHOULD_RUN="false"
fi
echo "DISK_USAGE_PCT=${DISK_USAGE_PCT}"
echo "DISK_USAGE_THRESHOLD_PCT=${DISK_USAGE_THRESHOLD_PCT}"
echo "DISK_CLEANUP_SHOULD_RUN=${DISK_CLEANUP_SHOULD_RUN}"
echo ""

if [[ "${DISK_CLEANUP_SHOULD_RUN}" != "true" ]]; then
    log_success "Disk usage is below threshold; skipping remaining dry-run steps."
    emit_cleanup_candidates
    exit 0
fi

# Check if running as root or with sudo (needed for journal access)
if [[ $EUID -ne 0 ]]; then
   log_warning "Running without sudo - some checks may be limited"
   log_warning "Run with sudo for complete analysis"
   echo ""
fi

################################################################################
# CRITICAL SAFETY CHECK - Identify protected directories
################################################################################

log_critical "==================================================================="
log_critical "PROTECTED DIRECTORIES - THESE WILL NEVER BE TOUCHED:"
log_critical "==================================================================="
echo ""

PROTECTED_DIRS=(
    "/var/lib/jenkins/caches"
    "/var/lib/jenkins/.cache"
    "/var/lib/jenkins/tools"
)

for protected_dir in "${PROTECTED_DIRS[@]}"; do
    if [[ -d "$protected_dir" ]]; then
        SIZE=$(get_dir_size "$protected_dir")
        log_critical "✓ $protected_dir (Size: $SIZE) - CONTAINS BUILD DEPENDENCIES"
        
        # Check for node_modules, vendor, yarn, composer caches
        if [[ -d "$protected_dir" ]]; then
            NODE_MODULES_COUNT=$(find "$protected_dir" -type d -name "node_modules" 2>/dev/null | wc -l | tr -d ' ')
            VENDOR_COUNT=$(find "$protected_dir" -type d -name "vendor" 2>/dev/null | wc -l | tr -d ' ')
            YARN_COUNT=$(find "$protected_dir" -type d -name ".yarn" -o -name "yarn" 2>/dev/null | wc -l | tr -d ' ')
            
            [[ $NODE_MODULES_COUNT -gt 0 ]] && echo "    - Contains $NODE_MODULES_COUNT node_modules directories"
            [[ $VENDOR_COUNT -gt 0 ]] && echo "    - Contains $VENDOR_COUNT vendor directories"
            [[ $YARN_COUNT -gt 0 ]] && echo "    - Contains $YARN_COUNT yarn cache directories"
        fi
    fi
done

echo ""
log_critical "These directories are PROTECTED and cleanup script will NOT touch them"
echo ""

# ------------------------------------------------------------------------------
# Step 0: Fast "what's big" overview (adds no candidates)
# ------------------------------------------------------------------------------
log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 0/7: Top offenders (fast overview)"
log_info "═══════════════════════════════════════════════════════════════════"

if [[ -d "$JENKINS_HOME" ]]; then
  log_info "Top 20 under $JENKINS_HOME (2 levels):"
  du -hx --max-depth=2 "$JENKINS_HOME" 2>/dev/null | sort -hr | head -20 || true
else
  log_warning "Jenkins home not found: $JENKINS_HOME"
fi

if [[ -d /var/log ]]; then
  echo ""
  log_info "Top 15 under /var/log (2 levels):"
  du -hx --max-depth=2 /var/log 2>/dev/null | sort -hr | head -15 || true
fi

JENKINS_HOME_USED_BYTES="$(path_bytes "$JENKINS_HOME")"
VARLOG_USED_BYTES="$(path_bytes /var/log)"
add_step_metric "jenkins_home total" "$JENKINS_HOME_USED_BYTES" 0 "Report-only"
add_step_metric "/var/log total" "$VARLOG_USED_BYTES" 0 "Report-only"
echo ""

################################################################################
# Step 1: Analyze system journal logs
################################################################################

# ------------------------------------------------------------------------------
# Step 1: System journal logs (measure, don't guess)
# ------------------------------------------------------------------------------
log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 1/7: Analyzing system journal logs"
log_info "═══════════════════════════════════════════════════════════════════"

if [[ $EUID -eq 0 ]] && command -v journalctl >/dev/null 2>&1; then
  log_info "journalctl disk usage:"
  journalctl --disk-usage 2>/dev/null || true

JOURNAL_USED_BYTES=0
if [[ -d /var/log/journal ]]; then
JOURNAL_USED_BYTES="$(path_bytes /var/log/journal)"
fi

# reclaim is not known without actually vacuuming; keep as 0 but note it
add_step_metric "journald" "$JOURNAL_USED_BYTES" 0 "Used known; reclaim depends on vacuum policy"
  log_plan "If needed: journalctl --vacuum-time=7d (keeps last 7 days)"
  # Candidate is the ACTION, not a path; don't add to file here (your real script will execute it)
else
  log_warning "Skipping journal analysis (requires sudo + journalctl)"
fi
echo ""

################################################################################
# Step 2: Analyze Jenkins build histories
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 2/7: Jenkins Build Histories older than 60 days (REPORT ONLY)"
log_info "═══════════════════════════════════════════════════════════════════"

JENKINS_JOBS_DIR="/var/lib/jenkins/jobs"

if [[ ! -d "$JENKINS_JOBS_DIR" ]]; then
    log_warning "Jenkins jobs directory not found: $JENKINS_JOBS_DIR"
else
    BUILDS_SIZE=$(get_dir_size "$JENKINS_JOBS_DIR")
    log_info "Current jobs directory size: $BUILDS_SIZE"
    
    # Count builds older than 60 days
    OLD_BUILDS_COUNT=0
    OLD_BUILDS_SIZE=0
    
    echo ""
    echo "  Analyzing builds older than 60 days..."
    
    # Show first 10 samples
    find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | head -10 | while read -r build_dir; do
        JOB_NAME=$(echo "$build_dir" | sed 's|/var/lib/jenkins/jobs/||' | sed 's|/builds/.*||')
        BUILD_NUM=$(basename "$build_dir")
        echo "    - OLD BUILD (report-only): $JOB_NAME/builds/$BUILD_NUM"
    done
    
    # Count with progress indicator
    (
        SECONDS=0
        while kill -0 $$ 2>/dev/null; do
            echo "Analysing ${SECONDS}(s)..."
            sleep 10
        done
    ) &
    PROGRESS_PID=$!
    
    OLD_BUILDS_TMP_FILE=$(mktemp)
    find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null \
        > "$OLD_BUILDS_TMP_FILE" || true

    OLD_BUILDS_COUNT=$(wc -l < "$OLD_BUILDS_TMP_FILE" | tr -d ' ')
    
    rm -f "$OLD_BUILDS_TMP_FILE"
    
    kill $PROGRESS_PID 2>/dev/null || true
    wait $PROGRESS_PID 2>/dev/null || true
    if [[ $OLD_BUILDS_COUNT -gt 0 ]]; then
        log_plan "Found $OLD_BUILDS_COUNT build directories older than 60 days"
        log_plan "Estimated savings: 20-30GB"
    else
        log_success "No builds older than 60 days found"
    fi
    
    # Show what's being kept
    RECENT_BUILDS_COUNT=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime -60 2>/dev/null | wc -l | tr -d ' ')
    log_success "Will preserve $RECENT_BUILDS_COUNT recent builds (< 60 days old)"

    BUILDS_USED_BYTES=0
    if [[ -d "$JENKINS_JOBS_DIR" ]]; then
    # Sum sizes of all "builds" dirs (not entire jobs dir)
    BUILDS_USED_BYTES="$(find "$JENKINS_JOBS_DIR" -type d -name builds -prune -exec du -sb {} + 2>/dev/null \
        | awk '{s+=$1} END{print s+0}')"
    fi
    add_step_metric "jenkins builds" "$BUILDS_USED_BYTES" 0 "Report-only; delete via Jenkins retention/API"
fi

echo ""

################################################################################
# Step 3: Analyze largest Jenkins builds directories
################################################################################

log_info "==================================================================="
log_info "STEP 3/7: Top 50 Jenkins builds directories by size (REPORT ONLY)"
log_info "==================================================================="

if [[ -d "$JENKINS_JOBS_DIR" ]]; then
  TOP_BUILDS_LIST=$(find "$JENKINS_JOBS_DIR" -type d -name builds -prune -exec du -x -B1 -s {} + 2>/dev/null \
    | sort -nr | head -50 || true)
  TOP_BUILDS_COUNT=$(printf '%s' "$TOP_BUILDS_LIST" | awk 'END {print NR+0}')

  if [[ $TOP_BUILDS_COUNT -gt 0 ]]; then
    echo ""
    echo "  Largest builds directories (size  path):"
    printf '%s\n' "$TOP_BUILDS_LIST" | while read -r bytes path; do
      printf "    - %s\t%s\n" "$(format_bytes "$bytes")" "$path"
    done

    TOP_BUILDS_TOTAL_BYTES=$(printf '%s\n' "$TOP_BUILDS_LIST" | awk '{sum+=$1} END {print sum+0}')
    log_plan "Top 50 builds dirs account for $(format_bytes "$TOP_BUILDS_TOTAL_BYTES")"
    log_plan "Action: reduce via Jenkins retention, not rm."
  else
    log_success "No builds directories found"
    TOP_BUILDS_TOTAL_BYTES=0
  fi
else
  TOP_BUILDS_TOTAL_BYTES=0
fi

add_step_metric "top builds dirs (50)" "$TOP_BUILDS_TOTAL_BYTES" 0 "Report-only subset of builds"

echo ""

################################################################################
# Step 4: Analyze old large files in Jenkins
################################################################################

log_info "==================================================================="
log_info "STEP 4/7: Old large files in Jenkins (mtime > 60d, size >= 100MB)"
log_info "==================================================================="

OLD_LARGE_TOTAL_BYTES=0

if [[ ! -d "$JENKINS_HOME" ]]; then
  log_warning "Jenkins home directory not found: $JENKINS_HOME"
else
  OLD_LARGE_LIST=$(find "$JENKINS_HOME" -type f -mtime +60 -size +100M \
    -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null \
    | sort -nr -k1,1 | head -50 || true)

  OLD_LARGE_COUNT=$(printf '%s' "$OLD_LARGE_LIST" | awk 'END {print NR+0}')

  if [[ $OLD_LARGE_COUNT -gt 0 ]]; then
    echo ""
    echo "  Old large files (date  size  path):"
    printf '%s\n' "$OLD_LARGE_LIST" | while IFS=$'\t' read -r bytes mtime path; do
      printf "    - %s\t%s\t%s\n" "$mtime" "$(format_bytes "$bytes")" "$path"
    done

    OLD_LARGE_TOTAL_BYTES=$(printf '%s\n' "$OLD_LARGE_LIST" | awk -F'\t' '{sum+=$1} END {print sum+0}')
    log_plan "Found $OLD_LARGE_COUNT old large files"
    log_plan "Estimated savings: $(format_bytes "$OLD_LARGE_TOTAL_BYTES") (if cleaned)"
    log_warning "Review each file before deleting; not auto-candidating these by default."
  else
    log_success "No old large files found (>=100MB, >60 days)"
  fi
fi

add_step_metric "old large files" "$OLD_LARGE_TOTAL_BYTES" 0 "Report-only; manual review before delete"

echo ""

################################################################################
# Step 6: Workspaces (general + PR) (SAFE candidates, age-gated)
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 6/8: Workspaces analysis (age-gated candidates)"
log_info "═══════════════════════════════════════════════════════════════════"

JENKINS_WORKSPACE_DIR="$JENKINS_HOME/workspace"
WORKSPACE_AGE_DAYS="${WORKSPACE_AGE_DAYS:-7}"

if [[ ! -d "$JENKINS_WORKSPACE_DIR" ]]; then
  log_warning "Jenkins workspace directory not found: $JENKINS_WORKSPACE_DIR"
else
  WORKSPACE_SIZE=$(get_dir_size "$JENKINS_WORKSPACE_DIR")
  log_info "Current workspace directory size: $WORKSPACE_SIZE"

  echo ""
  log_info "General old workspaces (top-level, mtime > ${WORKSPACE_AGE_DAYS}d):"
  OLD_WS_TMP="$(mktemp)"
  find "$JENKINS_WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$WORKSPACE_AGE_DAYS" 2>/dev/null > "$OLD_WS_TMP" || true
  OLD_WS_COUNT="$(wc -l < "$OLD_WS_TMP" | tr -d ' ')"

  if [[ "$OLD_WS_COUNT" -gt 0 ]]; then
    echo "  Sample (first 10):"
    head -10 "$OLD_WS_TMP" | while read -r ws; do
      echo "    - $(basename "$ws") (Size: $(get_dir_size "$ws"))"
      add_candidate "WORKSPACE" "$ws"
    done
    # add the rest (without sizing each)
    tail -n +11 "$OLD_WS_TMP" | while read -r ws; do
      add_candidate "WORKSPACE" "$ws"
    done
    log_plan "Found $OLD_WS_COUNT old workspaces (safe to delete; Jenkins will recreate)"
  else
    log_success "No old top-level workspaces found"
  fi
  rm -f "$OLD_WS_TMP"

  echo ""
  log_info "PR workspaces (mtime > ${WORKSPACE_AGE_DAYS}d, name contains pr-):"
  OLD_PR_TMP="$(mktemp)"
  find "$JENKINS_WORKSPACE_DIR" -maxdepth 2 -type d -iname "*pr-*" -mtime +"$WORKSPACE_AGE_DAYS" 2>/dev/null > "$OLD_PR_TMP" || true
  OLD_PR_COUNT="$(wc -l < "$OLD_PR_TMP" | tr -d ' ')"

  if [[ "$OLD_PR_COUNT" -gt 0 ]]; then
    echo "  Sample (first 10):"
    head -10 "$OLD_PR_TMP" | while read -r pr; do
      echo "    - $(basename "$pr") (Size: $(get_dir_size "$pr"))"
    done
    # add as explicit PR_WORKSPACE candidates
    cat "$OLD_PR_TMP" | while read -r pr; do
      add_candidate "PR_WORKSPACE" "$pr"
    done
    log_plan "Found $OLD_PR_COUNT old PR workspaces (safe to delete)"
  else
    log_success "No old PR workspaces found"
  fi
  rm -f "$OLD_PR_TMP"

  ACTIVE_WORKSPACES=$(find "$JENKINS_WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime -"${WORKSPACE_AGE_DAYS}" 2>/dev/null | wc -l | tr -d ' ')
  log_success "Will preserve $ACTIVE_WORKSPACES recent workspaces (< ${WORKSPACE_AGE_DAYS} days)"
fi
echo ""

################################################################################
# Step 6: Analyze GitHub SCM probe cache
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 7/7: Analyzing GitHub SCM probe cache"
log_info "═══════════════════════════════════════════════════════════════════"

GITHUB_CACHE="/var/lib/jenkins/org.jenkinsci.plugins.github_branch_source.GitHubSCMProbe.cache"

if [[ -f "$GITHUB_CACHE" ]]; then
    CACHE_SIZE=$(get_dir_size "$GITHUB_CACHE")
    CACHE_AGE=$(find "$GITHUB_CACHE" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null || echo "Unknown")
    
    log_info "GitHub SCM cache file found"
    echo "  Size: $CACHE_SIZE"
    echo "  Last modified: $CACHE_AGE"
    
    log_plan "Will delete this cache file (Jenkins rebuilds automatically)"
    log_plan "Expected savings: ~256MB"
    log_success "Safe to delete - Jenkins regenerates this automatically"
    echo "$GITHUB_CACHE" >> "$CLEANUP_CANDIDATES_FILE"
else
    log_success "GitHub SCM probe cache not found or already cleaned"
fi

WORKSPACE_USED_BYTES=0
if [[ -d "$JENKINS_WORKSPACE_DIR" ]]; then
  WORKSPACE_USED_BYTES="$(path_bytes "$JENKINS_WORKSPACE_DIR")"
fi

# compute reclaim from candidates of type WORKSPACE/PR_WORKSPACE
WORKSPACE_RECLAIM_BYTES=0
if [[ -f "$CLEANUP_CANDIDATES_FILE" ]]; then
  WORKSPACE_RECLAIM_BYTES="$(awk -F'\t' '$1=="WORKSPACE"||$1=="PR_WORKSPACE"{print $2}' "$CLEANUP_CANDIDATES_FILE" \
    | while read -r p; do du -sb "$p" 2>/dev/null | awk '{print $1}'; done \
    | awk '{s+=$1} END{print s+0}')"
fi

add_step_metric "workspaces" "$WORKSPACE_USED_BYTES" "$WORKSPACE_RECLAIM_BYTES" "Reclaim = sum of workspace candidates"

echo ""
# ------------------------------------------------------------------------------
# Step 7: GitHub SCM probe cache (safe candidate)
# ------------------------------------------------------------------------------
log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 8/8: GitHub SCM probe cache"
log_info "═══════════════════════════════════════════════════════════════════"

GITHUB_CACHE="$JENKINS_HOME/org.jenkinsci.plugins.github_branch_source.GitHubSCMProbe.cache"

if [[ -f "$GITHUB_CACHE" ]]; then
  CACHE_SIZE=$(get_dir_size "$GITHUB_CACHE")
  CACHE_DATE=$(find "$GITHUB_CACHE" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null || echo "Unknown")

  log_info "GitHub SCM cache file found"
  echo "  Size: $CACHE_SIZE"
  echo "  Last modified: $CACHE_DATE"

  log_plan "Will delete this cache file (Jenkins rebuilds automatically)"
  log_success "Safe to delete - Jenkins regenerates this automatically"
  add_candidate "CACHE_FILE" "$GITHUB_CACHE"
else
  log_success "GitHub SCM probe cache not found"
fi

CACHE_USED_BYTES=0
CACHE_RECLAIM_BYTES=0
if [[ -f "$GITHUB_CACHE" ]]; then
  CACHE_USED_BYTES="$(path_bytes "$GITHUB_CACHE")"
  CACHE_RECLAIM_BYTES="$CACHE_USED_BYTES"
fi
add_step_metric "github probe cache" "$CACHE_USED_BYTES" "$CACHE_RECLAIM_BYTES" "Safe to delete; rebuilds"

echo ""



# ------------------------------------------------------------------------------
# Step 8: jenkins.zip backup (safe candidate if truly a leftover archive)
# ------------------------------------------------------------------------------
log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 8/8: jenkins.zip backup"
log_info "═══════════════════════════════════════════════════════════════════"

JENKINS_ZIP="/var/lib/jenkins.zip"
ZIP_AGE_DAYS="${ZIP_AGE_DAYS:-30}"

if [[ -f "$JENKINS_ZIP" ]]; then
  ZIP_SIZE=$(get_dir_size "$JENKINS_ZIP")
  ZIP_DATE=$(find "$JENKINS_ZIP" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null || echo "Unknown")
  log_info "jenkins.zip found"
  echo "  Size: $ZIP_SIZE"
  echo "  Date: $ZIP_DATE"

  if find "$JENKINS_ZIP" -mtime +"$ZIP_AGE_DAYS" >/dev/null 2>&1; then
    log_plan "File is older than ${ZIP_AGE_DAYS} days - candidate for deletion"
    add_candidate "JENKINS_ZIP" "$JENKINS_ZIP"
  else
    log_success "File is recent (< ${ZIP_AGE_DAYS} days) - will be kept"
  fi
else
  log_success "jenkins.zip not found"
fi
echo ""

################################################################################
# SAFETY VERIFICATION
################################################################################

log_critical "═══════════════════════════════════════════════════════════════════"
log_critical "SAFETY VERIFICATION - PROTECTED PATHS CHECK"
log_critical "═══════════════════════════════════════════════════════════════════"
echo ""

# Double-check that we're not going to touch protected directories
log_success "✓ /var/lib/jenkins/caches - WILL NOT BE TOUCHED"
log_success "✓ /var/lib/jenkins/tools - WILL NOT BE TOUCHED"
log_success "✓ Active workspaces (< 7 days) - WILL NOT BE TOUCHED"
log_warning "✗ Build history directories are NOT candidates (must be deleted via Jenkins retention/API)."


echo ""

################################################################################
# Summary
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "SUMMARY - ESTIMATED SPACE RECOVERY"
log_info "═══════════════════════════════════════════════════════════════════"
echo ""

echo "Current disk usage: ${DISK_USAGE_RAW:-$(get_disk_usage)}"
echo ""

# ---------------------------------------------------------------------------
# Per-step disk usage (USED vs POTENTIAL RECLAIM)
# These values come from add_step_metric(...) calls in each step
# ---------------------------------------------------------------------------
print_step_metrics

# ---------------------------------------------------------------------------
# Reclaim grouped by cleanup candidate type (WORKSPACE, PR_WORKSPACE, CACHE_FILE, etc.)
# These values are computed from the candidates file using du -sb
# ---------------------------------------------------------------------------
print_candidate_reclaim_by_type

# ---------------------------------------------------------------------------
# Safety notes (no estimates, just guarantees)
# ---------------------------------------------------------------------------
echo ""
log_warning "SAFETY NOTES:"
log_warning "- Build history under ${JENKINS_HOME:-/var/lib/jenkins}/jobs/**/builds is Jenkins state."
log_warning "- Build directories are REPORT-ONLY here and must NOT be deleted via filesystem."
log_warning "- Build cleanup must be done via Jenkins retention or Jenkins API (build.delete())."
log_warning "- Workspace and cache candidates are age-gated and safe to delete."
echo ""

# ---------------------------------------------------------------------------
# Machine-readable output for automation
# ---------------------------------------------------------------------------
log_success "═══════════════════════════════════════════════════════════════════"
log_info "Machine-readable cleanup candidates (for automation)"
emit_cleanup_candidates
echo ""
log_success "DRY RUN COMPLETE - NO CHANGES WERE MADE"
log_success "═══════════════════════════════════════════════════════════════════"
echo ""

echo "Next steps:"
echo "  1. Review the per-step table above (USED vs RECLAIM)"
echo "  2. Review reclaim totals by candidate type"
echo "  3. Confirm Jenkins build retention is configured (preferred cleanup method)"
echo "  4. If acceptable, run the real cleanup script:"
echo "     sudo ./jenkins_disk_cleanup.sh"
echo ""
log_warning "IMPORTANT: The cleanup script has built-in protections and will NOT"
log_warning "delete /var/lib/jenkins/caches or other critical build dependencies"

echo ""
################################################################################
# Full cleanup candidates list with size and total (final output)
################################################################################

TOP_HEAVIEST_CANDIDATES="${TOP_HEAVIEST_CANDIDATES:-50}"

log_info "CLEANUP CANDIDATES WITH SIZES (TOP HEAVIEST)"
if [[ -f "$CLEANUP_CANDIDATES_FILE" ]]; then
    TOTAL_CANDIDATES_BYTES=0
    MISSING_CANDIDATES=0
    CANDIDATE_SIZES_FILE=$(mktemp)
    declare -A SEEN_CANDIDATES=()

    while IFS=$'\t' read -r typ candidate_path || [[ -n "${typ:-}" ]]; do
        [[ -z "${typ:-}" || -z "${candidate_path:-}" ]] && continue
        candidate_path="${candidate_path%$'\r'}"

        key="${typ}|${candidate_path}"
        if [[ -n "${SEEN_CANDIDATES[$key]:-}" ]]; then
            continue
        fi
        SEEN_CANDIDATES["$key"]=1

        if [[ -e "$candidate_path" ]]; then
            CANDIDATE_BYTES=$(get_dir_size_bytes "$candidate_path")
            TOTAL_CANDIDATES_BYTES=$((TOTAL_CANDIDATES_BYTES + CANDIDATE_BYTES))
            printf "%s\t%s\t%s\n" "$CANDIDATE_BYTES" "$typ" "$candidate_path" >> "$CANDIDATE_SIZES_FILE"
        else
            MISSING_CANDIDATES=$((MISSING_CANDIDATES + 1))
        fi
    done < "$CLEANUP_CANDIDATES_FILE"

    if [[ -s "$CANDIDATE_SIZES_FILE" ]]; then
        echo "Top ${TOP_HEAVIEST_CANDIDATES} heaviest candidates:"
        sort -nr "$CANDIDATE_SIZES_FILE" \
            | head -n "$TOP_HEAVIEST_CANDIDATES" \
            | while IFS=$'\t' read -r bytes typ candidate_path; do
                printf "  - %s\t%s\t%s\n" "$(format_bytes "$bytes")" "$typ" "$candidate_path"
            done
    else
        log_warning "No existing cleanup candidates found to size"
    fi

    echo "CLEANUP_CANDIDATES_WITH_SIZE_BEGIN"
    if [[ -s "$CANDIDATE_SIZES_FILE" ]]; then
        sort -nr "$CANDIDATE_SIZES_FILE"
    fi
    echo "CLEANUP_CANDIDATES_WITH_SIZE_END"

    if [[ "$MISSING_CANDIDATES" -gt 0 ]]; then
        log_warning "Missing candidates skipped from size ranking: $MISSING_CANDIDATES"
    fi

    echo "Total candidates size: $(format_bytes "$TOTAL_CANDIDATES_BYTES")"
    rm -f "$CANDIDATE_SIZES_FILE"
else
    log_warning "Candidates file not found: $CLEANUP_CANDIDATES_FILE"
    echo "CLEANUP_CANDIDATES_WITH_SIZE_BEGIN"
    echo "CLEANUP_CANDIDATES_WITH_SIZE_END"
fi
