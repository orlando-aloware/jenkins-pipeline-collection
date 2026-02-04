#!/bin/bash

################################################################################
# Jenkins Disk Cleanup Script
# Date: January 22, 2026
# Purpose: Safely reclaim disk space on Jenkins server
# Expected savings: 25-40GB (reducing usage from 69% to 35-45%)
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_plan() {
    echo -e "${CYAN}[PLAN]${NC} $1"
}

# Function to get disk usage
get_disk_usage() {
    df -h / | tail -1 | awk '{print $5}'
}

# Function to calculate directory size
get_dir_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"
}

################################################################################
# Pre-cleanup checks
################################################################################

# Check if running in dry-run mode
# Accept DRY_RUN_CLEANUP from environment or as first argument
if [[ "${1:-}" == "--dry-run" ]] || [[ "${1:-}" == "-n" ]]; then
    DRY_RUN="true"
elif [[ "${DRY_RUN_CLEANUP:-}" == "true" ]]; then
    DRY_RUN="true"
else
    DRY_RUN="false"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY-RUN mode - NO changes will be made"
    log_warning "This will analyze what would be cleaned without deleting anything"
    echo ""
else
    log_info "Running in NORMAL mode - Changes will be made"
    log_info "To run in dry-run mode: sudo ./jenkins_disk_cleanup.sh --dry-run"
    echo ""
fi

log_info "Starting Jenkins disk cleanup process..."
log_info "Current disk usage: $(get_disk_usage)"
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root or with sudo"
   exit 1
fi

# Confirm before proceeding (skip in dry-run mode)
if [[ "$DRY_RUN" != "true" ]]; then
    read -p "This will clean Jenkins logs, old builds, and workspaces. Continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_warning "Cleanup cancelled by user"
        exit 0
    fi
fi

################################################################################
# Step 1: Clean system journal logs
################################################################################

log_info "Step 1/5: Cleaning system journal logs..."
JOURNAL_SIZE_BEFORE=$(get_dir_size /var/log/journal)
log_info "Journal size before: $JOURNAL_SIZE_BEFORE"

if [[ "$DRY_RUN" == "true" ]]; then
    log_plan "Would run: journalctl --vacuum-time=7d"
    log_plan "Expected savings: ~4GB (keeps last 7 days only)"
else
    journalctl --vacuum-time=7d
    JOURNAL_SIZE_AFTER=$(get_dir_size /var/log/journal)
    log_success "Journal logs cleaned. Size after: $JOURNAL_SIZE_AFTER"
fi
echo ""

################################################################################
# Step 2: Remove old Jenkins build histories (older than 60 days)
################################################################################

log_info "Step 2/5: Removing Jenkins builds older than 60 days..."
JENKINS_JOBS_DIR="/var/lib/jenkins/jobs"

if [[ ! -d "$JENKINS_JOBS_DIR" ]]; then
    log_warning "Jenkins jobs directory not found: $JENKINS_JOBS_DIR"
else
    BUILDS_SIZE_BEFORE=$(get_dir_size $JENKINS_JOBS_DIR)
    log_info "Jenkins jobs size before: $BUILDS_SIZE_BEFORE"
    
    DELETED_COUNT=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        # Show sample of first 10 builds that would be deleted
        echo "  Analyzing builds older than 60 days..."
        find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | head -10 | while read -r build_dir; do
            JOB_NAME=$(echo "$build_dir" | sed 's|/var/lib/jenkins/jobs/||' | sed 's|/builds/.*||')
            BUILD_NUM=$(basename "$build_dir")
            echo "    - Would delete: $JOB_NAME/builds/$BUILD_NUM"
        done
        
        # Count what would be deleted with progress indicator
        (
            SECONDS=0
            while kill -0 $$ 2>/dev/null; do
                echo "Analysing ${SECONDS}(s)..."
                sleep 10
            done
        ) &
        PROGRESS_PID=$!
        
        DELETED_COUNT=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | wc -l | tr -d ' ')
        
        kill $PROGRESS_PID 2>/dev/null || true
        wait $PROGRESS_PID 2>/dev/null || true
        
        log_plan "Found $DELETED_COUNT build directories older than 60 days"
        log_plan "Estimated savings: 20-30GB"
        
        # Show what's being kept
        RECENT_BUILDS_COUNT=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime -60 2>/dev/null | wc -l | tr -d ' ')
        log_success "Will preserve $RECENT_BUILDS_COUNT recent builds (< 60 days old)"
    else
        # Show sample of builds being deleted
        echo "  Analyzing builds older than 60 days..."
        find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | head -10 | while read -r build_dir; do
            JOB_NAME=$(echo "$build_dir" | sed 's|/var/lib/jenkins/jobs/||' | sed 's|/builds/.*||')
            BUILD_NUM=$(basename "$build_dir")
            echo "    - Will delete: $JOB_NAME/builds/$BUILD_NUM"
        done
        
        # Count with progress indicator
        (
            SECONDS=0
            while kill -0 $$ 2>/dev/null; do
                echo "Counting ${SECONDS}(s)..."
                sleep 10
            done
        ) &
        PROGRESS_PID=$!
        
        TOTAL_TO_DELETE=$(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 2>/dev/null | wc -l | tr -d ' ')
        
        kill $PROGRESS_PID 2>/dev/null || true
        wait $PROGRESS_PID 2>/dev/null || true
        
        log_info "Found $TOTAL_TO_DELETE build directories to delete"
        log_info "Starting deletion..."
        
        # Find and delete build directories older than 60 days - only direct subdirectories
        while IFS= read -r -d '' build_dir; do
            rm -rf "$build_dir"
            ((DELETED_COUNT++))
            if ((DELETED_COUNT % 1000 == 0)); then
                echo "  Deleted $DELETED_COUNT / $TOTAL_TO_DELETE builds..."
            fi
        done < <(find "$JENKINS_JOBS_DIR" -type d -path "*/builds/*" ! -path "*/builds/*/*" -mtime +60 -print0 2>/dev/null)
        
        BUILDS_SIZE_AFTER=$(get_dir_size $JENKINS_JOBS_DIR)
        log_success "Deleted $DELETED_COUNT old builds. Size after: $BUILDS_SIZE_AFTER"
    fi
fi
echo ""

################################################################################
# Step 3: Clean old PR workspaces (older than 7 days)
################################################################################

log_info "Step 3/5: Cleaning old PR workspaces (older than 7 days)..."
JENKINS_WORKSPACE_DIR="/var/lib/jenkins/workspace"

if [[ ! -d "$JENKINS_WORKSPACE_DIR" ]]; then
    log_warning "Jenkins workspace directory not found: $JENKINS_WORKSPACE_DIR"
else
    WORKSPACE_SIZE_BEFORE=$(get_dir_size $JENKINS_WORKSPACE_DIR)
    log_info "Workspace size before: $WORKSPACE_SIZE_BEFORE"
    
    # Find and delete PR workspace directories older than 7 days
    # Looking for patterns like PR-123, pr-456, etc.
    DELETED_WS_COUNT=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        # Count what would be deleted
        DELETED_WS_COUNT=$(find "$JENKINS_WORKSPACE_DIR" -maxdepth 2 -type d -iname "*pr-*" -mtime +7 2>/dev/null | wc -l | tr -d ' ')
        log_plan "Would delete $DELETED_WS_COUNT old PR workspaces"
        log_plan "Estimated savings: 1-5GB"
        
        # Show sample of first 5 PR workspaces that would be deleted
        if [[ $DELETED_WS_COUNT -gt 0 ]]; then
            echo "  Sample of PR workspaces that would be deleted:"
            find "$JENKINS_WORKSPACE_DIR" -maxdepth 2 -type d -iname "*pr-*" -mtime +7 2>/dev/null | head -5 | while read -r pr_dir; do
                PR_SIZE=$(get_dir_size "$pr_dir")
                PR_NAME=$(basename "$pr_dir")
                echo "    - $PR_NAME (Size: $PR_SIZE)"
            done
        fi
    else
        while IFS= read -r -d '' pr_dir; do
            rm -rf "$pr_dir"
            ((DELETED_WS_COUNT++))
        done < <(find "$JENKINS_WORKSPACE_DIR" -maxdepth 2 -type d -iname "*pr-*" -mtime +7 -print0 2>/dev/null)
        
        WORKSPACE_SIZE_AFTER=$(get_dir_size $JENKINS_WORKSPACE_DIR)
        log_success "Deleted $DELETED_WS_COUNT old PR workspaces. Size after: $WORKSPACE_SIZE_AFTER"
    fi
fi
echo ""

################################################################################
# Step 4: Clear GitHub SCM probe cache
################################################################################

log_info "Step 4/5: Clearing GitHub SCM probe cache..."
GITHUB_CACHE="/var/lib/jenkins/org.jenkinsci.plugins.github_branch_source.GitHubSCMProbe.cache"

if [[ -f "$GITHUB_CACHE" ]]; then
    CACHE_SIZE=$(get_dir_size "$GITHUB_CACHE")
    log_info "GitHub SCM cache size: $CACHE_SIZE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_plan "Would delete GitHub SCM probe cache"
        log_plan "Expected savings: ~256MB"
    else
        rm -f "$GITHUB_CACHE"
        log_success "GitHub SCM probe cache deleted (Jenkins will rebuild automatically)"
    fi
else
    log_warning "GitHub SCM probe cache not found: $GITHUB_CACHE"
fi
echo ""

################################################################################
# Step 5: Verify and remove jenkins.zip backup
################################################################################

log_info "Step 5/5: Checking jenkins.zip backup..."
JENKINS_ZIP="/var/lib/jenkins.zip"

if [[ -f "$JENKINS_ZIP" ]]; then
    log_info "Found jenkins.zip backup:"
    ls -lh "$JENKINS_ZIP"
    
    # Check if file is older than 30 days
    if [[ $(find "$JENKINS_ZIP" -mtime +30 2>/dev/null) ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            ZIP_SIZE=$(get_dir_size "$JENKINS_ZIP")
            log_plan "jenkins.zip is older than 30 days - would prompt for deletion"
            log_plan "Expected savings: $ZIP_SIZE"
        else
            read -p "jenkins.zip is older than 30 days. Remove it? (yes/no): " -r
            echo
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                rm -f "$JENKINS_ZIP"
                log_success "jenkins.zip backup removed"
            else
                log_info "Keeping jenkins.zip backup"
            fi
        fi
    else
        log_info "jenkins.zip is recent (< 30 days old), keeping it"
    fi
else
    log_info "jenkins.zip backup not found"
fi
echo ""

################################################################################
# Post-cleanup summary
################################################################################

log_info "==============================================="
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY-RUN Analysis completed!"
else
    log_info "Cleanup completed!"
fi
log_info "==============================================="
log_info "Final disk usage: $(get_disk_usage)"
echo ""

log_info "Disk usage breakdown:"
df -h /
echo ""

log_info "Jenkins directories sizes:"
echo "  Jobs:      $(get_dir_size /var/lib/jenkins/jobs)"
echo "  Workspace: $(get_dir_size /var/lib/jenkins/workspace)"
echo "  Caches:    $(get_dir_size /var/lib/jenkins/caches) (PROTECTED - contains build dependencies)"
echo "  Logs:      $(get_dir_size /var/lib/jenkins/logs)"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE - No changes were made"
    log_info "To execute cleanup: sudo ./jenkins_disk_cleanup.sh"
else
    log_warning "IMPORTANT: Monitor Jenkins builds to ensure everything works correctly"
    log_warning "If issues occur, recent builds (< 60 days) are preserved for rollback"
fi
echo ""

log_success "Process completed successfully!"
