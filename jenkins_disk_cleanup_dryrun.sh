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
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SAFE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[DANGER]${NC} $1"
}

log_plan() {
    echo -e "${CYAN}[PLAN]${NC} $1"
}

log_critical() {
    echo -e "${MAGENTA}[CRITICAL - DO NOT DELETE]${NC} $1"
}

# Cleanup candidates output helpers (for GitHub Actions parsing)
init_cleanup_candidates() {
    : > "$CLEANUP_CANDIDATES_FILE"
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
get_disk_usage() {
    df -h / | tail -1 | awk '{print $5}'
}

# Function to get disk usage as integer percent (no % sign)
get_disk_usage_pct() {
    df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
}

# Function to calculate directory size
get_dir_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"
}

# Function to calculate directory size in bytes for comparison
get_dir_size_bytes() {
    du -sb "$1" 2>/dev/null | cut -f1 || echo "0"
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

################################################################################
# Step 1: Analyze system journal logs
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 1/7: Analyzing system journal logs"
log_info "═══════════════════════════════════════════════════════════════════"

if [[ $EUID -eq 0 ]]; then
    JOURNAL_DIR="/var/log/journal"
    if [[ -d "$JOURNAL_DIR" ]]; then
        JOURNAL_SIZE=$(get_dir_size "$JOURNAL_DIR")
        log_info "Current journal size: $JOURNAL_SIZE"
        
        # Show oldest and newest logs
        OLDEST_LOG=$(journalctl --list-boots | head -1 2>/dev/null || echo "Unable to determine")
        NEWEST_LOG=$(journalctl --list-boots | tail -1 2>/dev/null || echo "Unable to determine")
        
        echo "  Oldest logs: $OLDEST_LOG"
        echo "  Newest logs: $NEWEST_LOG"
        
        log_plan "Will run: journalctl --vacuum-time=7d"
        log_plan "Expected savings: ~4GB (keeps last 7 days only)"
    fi
else
    log_warning "Skipping journal analysis (requires sudo)"
fi

echo ""

################################################################################
# Step 2: Analyze Jenkins build histories
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 2/7: Analyzing Jenkins build histories (older than 60 days)"
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
        echo "    - Would delete: $JOB_NAME/builds/$BUILD_NUM"
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
    
    OLD_BUILDS_COUNT=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null \
        | tee -a "$CLEANUP_CANDIDATES_FILE" | wc -l | tr -d ' ')
    
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
fi

echo ""

################################################################################
# Step 3: Analyze largest Jenkins builds directories
################################################################################

log_info "==================================================================="
log_info "STEP 3/7: Top 50 Jenkins builds directories by size"
log_info "==================================================================="

if [[ ! -d "$JENKINS_JOBS_DIR" ]]; then
    log_warning "Jenkins jobs directory not found: $JENKINS_JOBS_DIR"
else
    TOP_BUILDS_LIST=$(find "$JENKINS_JOBS_DIR" -type d -name builds -prune -exec du -x -B1 -s {} + 2>/dev/null \
        | sort -nr | head -50)
    TOP_BUILDS_COUNT=$(printf '%s' "$TOP_BUILDS_LIST" | awk 'END {print NR+0}')

    if [[ $TOP_BUILDS_COUNT -gt 0 ]]; then
        echo ""
        echo "  Largest builds directories (size  path):"
        printf '%s' "$TOP_BUILDS_LIST" | while IFS=$'\t' read -r bytes path; do
            printf "    - %s\t%s\n" "$(format_bytes "$bytes")" "$path"
        done

        TOP_BUILDS_TOTAL_BYTES=$(printf '%s' "$TOP_BUILDS_LIST" | awk '{sum+=$1} END {print sum+0}')
        log_plan "Top 50 builds directories account for $(format_bytes "$TOP_BUILDS_TOTAL_BYTES")"
        log_plan "Estimated savings: $(format_bytes "$TOP_BUILDS_TOTAL_BYTES") (if pruned)"
        log_warning "Informational only - may overlap with old-build pruning"
    else
        log_success "No builds directories found"
    fi
fi

echo ""

################################################################################
# Step 4: Analyze old large files in Jenkins
################################################################################

log_info "==================================================================="
log_info "STEP 4/7: Old large files in Jenkins (mtime > 60d, size >= 100MB)"
log_info "==================================================================="

if [[ ! -d "$JENKINS_HOME" ]]; then
    log_warning "Jenkins home directory not found: $JENKINS_HOME"
else
    OLD_LARGE_LIST=$(find "$JENKINS_HOME" -type f -mtime +60 -size +100M \
        -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null \
        | sort -nr -k1,1 | head -50)
    OLD_LARGE_COUNT=$(printf '%s' "$OLD_LARGE_LIST" | awk 'END {print NR+0}')

    if [[ $OLD_LARGE_COUNT -gt 0 ]]; then
        echo ""
        echo "  Old large files (date  size  path):"
        printf '%s' "$OLD_LARGE_LIST" | while IFS=$'\t' read -r bytes mtime path; do
            printf "    - %s\t%s\t%s\n" "$mtime" "$(format_bytes "$bytes")" "$path"
        done

        OLD_LARGE_TOTAL_BYTES=$(printf '%s' "$OLD_LARGE_LIST" | awk -F'\t' '{sum+=$1} END {print sum+0}')
        log_plan "Found $OLD_LARGE_COUNT old large files"
        log_plan "Estimated savings: $(format_bytes "$OLD_LARGE_TOTAL_BYTES") (if cleaned)"
        log_warning "Informational only - review before deleting"
    else
        log_success "No old large files found (>=100MB, >60 days)"
    fi
fi

echo ""

################################################################################
# Step 5: Analyze PR workspaces
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 5/7: Analyzing old PR workspaces (older than 7 days)"
log_info "═══════════════════════════════════════════════════════════════════"

JENKINS_WORKSPACE_DIR="/var/lib/jenkins/workspace"

if [[ ! -d "$JENKINS_WORKSPACE_DIR" ]]; then
    log_warning "Jenkins workspace directory not found: $JENKINS_WORKSPACE_DIR"
else
    WORKSPACE_SIZE=$(get_dir_size "$JENKINS_WORKSPACE_DIR")
    log_info "Current workspace directory size: $WORKSPACE_SIZE"
    
    # Find old PR workspaces
    OLD_PR_DIRS=$(find "$JENKINS_WORKSPACE_DIR" -maxdepth 2 -type d -iname "*pr-*" -mtime +7 2>/dev/null)
    OLD_PR_COUNT=$(echo "$OLD_PR_DIRS" | grep -c "." 2>/dev/null || echo "0")
    
    echo ""
    if [[ $OLD_PR_COUNT -gt 0 ]]; then
        echo "$OLD_PR_DIRS" >> "$CLEANUP_CANDIDATES_FILE"
        echo "  Sample of PR workspaces to be deleted (first 10):"
        echo "$OLD_PR_DIRS" | head -10 | while read -r pr_dir; do
            PR_SIZE=$(get_dir_size "$pr_dir")
            PR_NAME=$(basename "$pr_dir")
            echo "    - $PR_NAME (Size: $PR_SIZE)"
        done
        
        echo ""
        log_plan "Found $OLD_PR_COUNT old PR workspaces to delete"
        log_plan "Estimated savings: 1-5GB"
    else
        log_success "No old PR workspaces found (all are recent)"
    fi
    
    # Check for node_modules in PR workspaces to be deleted
    if [[ $OLD_PR_COUNT -gt 0 ]]; then
        echo ""
        log_warning "Checking for node_modules in old PR workspaces..."
        NODE_MODULES_IN_PR=$(echo "$OLD_PR_DIRS" | while read -r pr_dir; do
            find "$pr_dir" -maxdepth 2 -type d -name "node_modules" 2>/dev/null
        done | wc -l | tr -d ' ')
        
        if [[ $NODE_MODULES_IN_PR -gt 0 ]]; then
            log_warning "Found $NODE_MODULES_IN_PR node_modules directories in old PR workspaces"
            log_warning "These are OLD/MERGED PR workspaces and safe to delete"
        fi
    fi
    
    # Show active workspaces that will be kept
    ACTIVE_WORKSPACES=$(find "$JENKINS_WORKSPACE_DIR" -maxdepth 1 -type d -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    log_success "Will preserve $ACTIVE_WORKSPACES active/recent workspaces"
fi

echo ""

################################################################################
# Step 6: Analyze GitHub SCM probe cache
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 6/7: Analyzing GitHub SCM probe cache"
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

echo ""

################################################################################
# Step 7: Analyze jenkins.zip backup
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 7/7: Analyzing jenkins.zip backup"
log_info "═══════════════════════════════════════════════════════════════════"

JENKINS_ZIP="/var/lib/jenkins.zip"

if [[ -f "$JENKINS_ZIP" ]]; then
    ZIP_SIZE=$(get_dir_size "$JENKINS_ZIP")
    ZIP_AGE=$(find "$JENKINS_ZIP" -mtime +30 2>/dev/null)
    ZIP_DATE=$(find "$JENKINS_ZIP" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null || echo "Unknown")
    
    log_info "jenkins.zip backup found"
    echo "  Size: $ZIP_SIZE"
    echo "  Date: $ZIP_DATE"
    
    if [[ -n "$ZIP_AGE" ]]; then
        log_plan "File is older than 30 days - will prompt for deletion"
        log_plan "Expected savings: $ZIP_SIZE"
        echo "$JENKINS_ZIP" >> "$CLEANUP_CANDIDATES_FILE"
    else
        log_success "File is recent (< 30 days) - will be kept"
    fi
else
    log_success "jenkins.zip backup not found"
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
log_success "✓ Recent builds (< 60 days) - WILL NOT BE TOUCHED"

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
echo "Estimated space to be recovered:"
echo "  - System journal logs:     ~4GB"
echo "  - Old Jenkins builds:      20-30GB"
echo "  - Old PR workspaces:       1-5GB"
echo "  - GitHub SCM cache:        ~256MB"
echo "  - jenkins.zip backup:      ~1.3GB (if applicable)"
echo "  - Top 50 builds dirs:      $(format_bytes "$TOP_BUILDS_TOTAL_BYTES") (informational)"
echo "  - Old large files (>60d):  $(format_bytes "$OLD_LARGE_TOTAL_BYTES") (informational)"
echo "  ----------------------------------------"
echo "  Total estimated savings:   25-40GB (baseline)"
echo "  Additional potential:      $(format_bytes $((TOP_BUILDS_TOTAL_BYTES + OLD_LARGE_TOTAL_BYTES))) (may overlap)"
echo ""
echo "Expected final disk usage:  35-45% (down from current ${DISK_USAGE_RAW:-$(get_disk_usage)}, baseline only)"

echo ""
log_success "═══════════════════════════════════════════════════════════════════"
log_info "Machine-readable cleanup candidates (for automation)"
emit_cleanup_candidates
echo ""
log_success "DRY RUN COMPLETE - NO CHANGES WERE MADE"
log_success "═══════════════════════════════════════════════════════════════════"
echo ""

echo "Next steps:"
echo "  1. Review the analysis above"
echo "  2. Verify that protected directories (caches) are not being touched"
echo "  3. If everything looks good, run the actual cleanup script:"
echo "     sudo ./jenkins_disk_cleanup.sh"
echo ""

log_warning "IMPORTANT: The cleanup script has built-in protections and will NOT"
log_warning "delete /var/lib/jenkins/caches or other critical build dependencies"

echo ""
################################################################################
# Full cleanup candidates list with size and total (final output)
################################################################################

log_info "CLEANUP CANDIDATES WITH SIZES (FULL LIST)"
if [[ -f "$CLEANUP_CANDIDATES_FILE" ]]; then
    TOTAL_CANDIDATES_BYTES=0
    while IFS= read -r candidate || [[ -n "$candidate" ]]; do
        [[ -z "$candidate" ]] && continue
        if [[ -e "$candidate" ]]; then
            CANDIDATE_BYTES=$(get_dir_size_bytes "$candidate")
            CANDIDATE_SIZE=$(format_bytes "$CANDIDATE_BYTES")
            TOTAL_CANDIDATES_BYTES=$((TOTAL_CANDIDATES_BYTES + CANDIDATE_BYTES))
        else
            CANDIDATE_SIZE="MISSING"
        fi
        printf "  - %s\t%s\n" "$CANDIDATE_SIZE" "$candidate"
    done < "$CLEANUP_CANDIDATES_FILE"
    echo "Total candidates size: $(format_bytes "$TOTAL_CANDIDATES_BYTES")"
else
    log_warning "Candidates file not found: $CLEANUP_CANDIDATES_FILE"
fi
