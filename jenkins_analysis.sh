#!/usr/bin/env bash
set -euo pipefail

THRESHOLD=95

rootfs="/"
jenkins_home="/var/lib/jenkins"

# ---------- helpers ----------
hr() { numfmt --to=iec --suffix=B --padding=7 "$1"; } 2>/dev/null || true

print_kv() { printf "%-40s %s\n" "$1" "$2"; }

top_dirs() {
  local maxdepth="$1"; shift
  local n="$1"; shift
  # Remaining args are paths
  sudo du -x -B1 --max-depth="$maxdepth" "$@" 2>/dev/null \
    | sort -nr \
    | head -n "$n" \
    | awk '{printf "%s\t%s\n",$1,$2}' \
    | while IFS=$'\t' read -r bytes path; do
        printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
      done
}

top_files() {
  local n="$1"; shift
  local min_size_bytes="$1"; shift
  # Use apparent size from stat via find -printf %s (fast, no du forks)
  # Stay on same filesystem with -xdev.
  sudo find "$rootfs" -xdev -type f -size +"${min_size_bytes}c" -printf '%s\t%p\n' 2>/dev/null \
    | sort -nr \
    | head -n "$n" \
    | while IFS=$'\t' read -r bytes path; do
        printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
      done
}

exists() { command -v "$1" >/dev/null 2>&1; }

# ---------- disk usage ----------
USAGE=$(df -P "$rootfs" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
echo "Disk usage is ${USAGE}% (threshold: ${THRESHOLD}%)"

# emergency cleanup actions
if [ "$USAGE" -ge "$THRESHOLD" ]; then
  echo "Emergency mode: enabled"
else
  echo "Emergency mode: disabled"
fi

echo
echo "Top 20 largest directories from / (depth=1, same filesystem):"
top_dirs 1 20 /

echo
echo "Top 20 largest directories in /var (depth=2):"
top_dirs 2 20 /var

echo
echo "Top 20 largest directories in ${jenkins_home} (depth=2):"
top_dirs 2 20 "$jenkins_home"

# Targeted Jenkins hotspots (cheap + actionable)
echo
echo "Sizes of key Jenkins directories:"
sudo du -x -B1 -s \
  "$jenkins_home"/{workspace,jobs,caches,logs,plugins} 2>/dev/null \
  | sort -nr \
  | while read -r bytes path; do
      printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
    done

echo
echo "Top 20 largest Jenkins jobs:"
sudo du -x -B1 -s "$jenkins_home/jobs/"* 2>/dev/null \
  | sort -nr | head -20 \
  | while read -r bytes path; do
      printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
    done

echo
echo "Top 50 Jenkins builds directories by size:"
sudo find "$jenkins_home/jobs" -type d -name builds -prune -exec du -x -B1 -s {} + 2>/dev/null \
  | sort -nr | head -50 \
  | while read -r bytes path; do
      printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
    done

# Replace the O(N^2) "most files" logic with a single traversal (depth=2 children count).
echo
echo "Top 20 Jenkins subdirectories with most immediate children (depth=1):"
sudo find "$jenkins_home" -mindepth 2 -maxdepth 2 -printf '%h\n' 2>/dev/null \
  | sort | uniq -c | sort -nr | head -20 \
  | awk '{count=$1; $1=""; sub(/^ /,""); printf "%8d  %s\n", count, $0}'

# Full-root large files scan is expensive; keep it, but do it efficiently and optionally gate it.
echo
echo "Top 50 largest files on / (same filesystem, >=100MB apparent size):"
top_files 50 $((100*1024*1024))

echo
echo "Old large files in ${jenkins_home} (mtime>60d, >=100MB):"
sudo find "$jenkins_home" -type f -mtime +60 -size +100M -printf '%TY-%Tm-%Td %TH:%TM\t%10s\t%p\n' 2>/dev/null \
  | sort -nr -k2,2 \
  | head -50 \
  | awk '{printf "%s\t%s\t%s\n",$1" "$2,(sprintf("%s", $3)),$4}'

echo
echo "Large log files in /var/log (>=50MB):"
sudo find /var/log -xdev -type f -size +50M -printf '%s\t%p\n' 2>/dev/null \
  | sort -nr | head -50 \
  | while IFS=$'\t' read -r bytes path; do
      printf "%s\t%s\n" "$(numfmt --to=iec --suffix=B "$bytes")" "$path"
    done

# Docker info can be slow; only run if docker exists (and optionally if usage is high).
if exists docker; then
  echo
  echo "Docker disk usage:"
  if [ "$USAGE" -ge "$THRESHOLD" ]; then
    sudo docker system df -v
  else
    sudo docker system df
  fi
fi

echo
echo "Current disk usage summary:"
df -h "$rootfs"
