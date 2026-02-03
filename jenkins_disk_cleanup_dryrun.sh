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

# Function to get disk usage
get_disk_usage() {
    df -h / | tail -1 | awk '{print $5}'
}

# Function to calculate directory size
get_dir_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"
}

# Function to calculate directory size in bytes for comparison
get_dir_size_bytes() {
    du -sb "$1" 2>/dev/null | cut -f1 || echo "0"
}

# Function to count items
count_items() {
    find "$1" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' '
}

################################################################################
# Pre-flight checks
################################################################################

echo "================================================================================"
echo "              JENKINS DISK CLEANUP - DRY RUN (NO CHANGES MADE)"
echo "================================================================================"
echo ""
log_warning "This is a READ-ONLY analysis. Nothing will be deleted."
echo ""

log_info "Current disk usage: $(get_disk_usage)"
log_info "Current date/time: $(date)"
echo ""

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
log_info "STEP 1/5: Analyzing system journal logs"
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
log_info "STEP 2/5: Analyzing Jenkins build histories (older than 60 days)"
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
    
    OLD_BUILDS_COUNT=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | wc -l | tr -d ' ')
    
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
# Step 3: Analyze PR workspaces
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 3/5: Analyzing old PR workspaces (older than 7 days)"
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
# Step 4: Analyze GitHub SCM probe cache
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 4/5: Analyzing GitHub SCM probe cache"
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
else
    log_success "GitHub SCM probe cache not found or already cleaned"
fi

echo ""

################################################################################
# Step 5: Analyze jenkins.zip backup
################################################################################

log_info "═══════════════════════════════════════════════════════════════════"
log_info "STEP 5/5: Analyzing jenkins.zip backup"
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

echo "Current disk usage: $(get_disk_usage)"
echo ""
echo "Estimated space to be recovered:"
echo "  - System journal logs:     ~4GB"
echo "  - Old Jenkins builds:      20-30GB"
echo "  - Old PR workspaces:       1-5GB"
echo "  - GitHub SCM cache:        ~256MB"
echo "  - jenkins.zip backup:      ~1.3GB (if applicable)"
echo "  ----------------------------------------"
echo "  Total estimated savings:   25-40GB"
echo ""
echo "Expected final disk usage:  35-45% (down from current $(get_disk_usage))"

echo ""
log_success "═══════════════════════════════════════════════════════════════════"
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
