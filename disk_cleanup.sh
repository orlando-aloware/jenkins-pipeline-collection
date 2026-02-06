#!/bin/bash

################################################################################
# Disk Cleanup Script (delete from candidate list)
# Purpose: Delete paths identified by the dry-run analysis
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_plan() { echo -e "${CYAN}[PLAN]${NC} $1"; }

usage() {
    cat << 'EOF'
Usage:
  ./disk_cleanup.sh --file /path/to/candidates.txt
  ./disk_cleanup.sh /path/to/candidates.txt
  echo "$CLEANUP_CANDIDATES" | ./disk_cleanup.sh

Inputs:
  - Newline-separated list of paths (files or directories).
  - If no file is provided, the script reads from STDIN.

Options:
  --file <path>     Read candidates from file
  --dry-run         Print what would be deleted without removing anything
EOF
}

DRY_RUN="false"
CANDIDATES_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN="true"
            shift
            ;;
        --file)
            CANDIDATES_FILE="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$CANDIDATES_FILE" && -f "$1" ]]; then
                CANDIDATES_FILE="$1"
                shift
            else
                log_error "Unknown argument: $1"
                usage
                exit 1
            fi
            ;;
    esac
done

if [[ -n "$CANDIDATES_FILE" && ! -f "$CANDIDATES_FILE" ]]; then
    log_error "Candidates file not found: $CANDIDATES_FILE"
    exit 1
fi

if [[ -z "$CANDIDATES_FILE" && -t 0 ]]; then
    log_error "No candidates file provided and no STDIN detected."
    usage
    exit 1
fi

PROTECTED_DIRS=(
    "/var/lib/jenkins/caches"
    "/var/lib/jenkins/.cache"
    "/var/lib/jenkins/tools"
)

BLOCKLIST_EXACT=(
    "/"
    "/var"
    "/var/lib"
    "/var/lib/jenkins"
    "/var/lib/jenkins/jobs"
    "/var/lib/jenkins/workspace"
    "/var/lib/jenkins/logs"
)

is_protected() {
    local path="$1"
    for p in "${PROTECTED_DIRS[@]}"; do
        if [[ "$path" == "$p" || "$path" == "$p/"* ]]; then
            return 0
        fi
    done
    return 1
}

is_blocked_exact() {
    local path="$1"
    for p in "${BLOCKLIST_EXACT[@]}"; do
        if [[ "$path" == "$p" ]]; then
            return 0
        fi
    done
    return 1
}

get_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sh -- "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "MISSING"
    fi
}

log_info "Starting cleanup from candidate list..."
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN mode enabled - no deletions will occur."
fi

declare -A SEEN
deleted=0
skipped=0
failed=0
total=0

read_candidates() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        if [[ -n "${SEEN[$line]:-}" ]]; then
            continue
        fi
        SEEN["$line"]=1
        total=$((total + 1))
        process_candidate "$line"
    done
}

process_candidate() {
    local path="$1"
    local size
    size="$(get_size "$path")"
    echo "CANDIDATE path=\"$path\" name=\"$(basename "$path")\" size=\"$size\""

    if is_blocked_exact "$path"; then
        log_warning "Skipping blocked path: $path"
        skipped=$((skipped + 1))
        echo "DELETE_RESULT path=\"$path\" status=SKIPPED reason=blocked"
        return
    fi

    if is_protected "$path"; then
        log_warning "Skipping protected path: $path"
        skipped=$((skipped + 1))
        echo "DELETE_RESULT path=\"$path\" status=SKIPPED reason=protected"
        return
    fi

    if [[ ! -e "$path" ]]; then
        log_warning "Path missing: $path"
        skipped=$((skipped + 1))
        echo "DELETE_RESULT path=\"$path\" status=SKIPPED reason=missing"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_plan "Would delete: $path"
        skipped=$((skipped + 1))
        echo "DELETE_RESULT path=\"$path\" status=DRY_RUN"
        return
    fi

    if rm -rf -- "$path"; then
        if [[ ! -e "$path" ]]; then
            log_success "Deleted: $path"
            deleted=$((deleted + 1))
            echo "DELETE_RESULT path=\"$path\" status=SUCCESS"
        else
            log_error "Delete failed (still exists): $path"
            failed=$((failed + 1))
            echo "DELETE_RESULT path=\"$path\" status=FAILED reason=still_exists"
        fi
    else
        log_error "Delete failed: $path"
        failed=$((failed + 1))
        echo "DELETE_RESULT path=\"$path\" status=FAILED"
    fi
}

if [[ -n "$CANDIDATES_FILE" ]]; then
    read_candidates < "$CANDIDATES_FILE"
else
    read_candidates
fi

log_info "Cleanup complete."
log_info "Summary: total=$total deleted=$deleted skipped=$skipped failed=$failed"

if [[ "$failed" -gt 0 ]]; then
    exit 2
fi
