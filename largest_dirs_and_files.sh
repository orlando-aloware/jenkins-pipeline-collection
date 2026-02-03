#!/bin/bash

# Check for usage above 95% and clean logs if so
USAGE=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')

if [ "$USAGE" -ge 95 ]; then
  echo "Disk usage is ${USAGE}% — emergency cleanup triggered"
  # sudo rm -f /var/log/*.gz
  # sudo rm -f /var/log/journal/*/*
else
  echo "Disk usage is ${USAGE}% — no action taken"
fi

# 1. Find top 20 largest directories from root
# sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20
echo "Top 20 largest directories from root:"
sudo du -h -x --max-depth=1 / 2>/dev/null | sort -hr | head -20
# sudo du -h -x --max-depth=1 /var /home /opt /srv 2>/dev/null | sort -hr


# 2. Find top 20 largest directories in /var
# We get subfolders of max depth to so we could get /var/lib/ and /var/lib/postgresql sizes too
echo "Top 20 largest directories in /var:"
sudo du -h -x --max-depth=2 /var 2>/dev/null | sort -hr | head -20
# sudo du -h -x --max-depth=1 /var 2>/dev/null | sort -hr | head -20

# 3. Find largest directories in Jenkins home
# Same situation here as number 2
echo "Top 20 largest directories in /var/lib/jenkins:"
sudo du -h -x --max-depth=2 /var/lib/jenkins 2>/dev/null | sort -hr | head -20
# sudo du -h -x --max-depth=1 /var/lib/jenkins 2>/dev/null | sort -hr | head -20

# 4. Find directories larger than 1GB anywhere
# This command is wrong, there are no directories with size +1G
# sudo find / -type d -size +1G 2>/dev/null -exec du -sh {} \; | sort -hr

# 5. Find top 50 largest files on the system
echo "Top 50 largest files on the system:"
sudo find / -type f -size +100M 2>/dev/null -exec du -h {} \; | sort -hr | head -50

# 6. Interactive disk usage analyzer (if installed)
#echo "Launching ncdu for /var/lib/jenkins (if installed)..."
#ncdu /var/lib/jenkins

# 7. Find large directories under /var/lib/jenkins specifically
echo "Top 50 largest directories/files in /var/lib/jenkins:"
sudo du -ah /var/lib/jenkins 2>/dev/null | sort -hr | head -50

# 8. Check each subdirectory size in Jenkins jobs
echo "Top 20 largest Jenkins jobs:"
sudo du -sh /var/lib/jenkins/jobs/* 2>/dev/null | sort -hr | head -20

# 9. Find directories with many files (can indicate bloat)
echo "Top 20 directories in /var/lib/jenkins with most files:"
sudo find /var/lib/jenkins -type d -exec sh -c 'echo "$(find "$1" -maxdepth 1 | wc -l) $1"' _ {} \; 2>/dev/null | sort -rn | head -20

# 10. Check specific Jenkins paths
echo "Sizes of key Jenkins directories:"
sudo du -sh /var/lib/jenkins/{workspace,jobs,caches,logs,plugins} 2>/dev/null

# 11. Find old large files (not modified in 60+ days)
echo "Old large files in /var/lib/jenkins (not modified in 60+ days):"
sudo find /var/lib/jenkins -type f -mtime +60 -size +100M -exec ls -lh {} \; 2>/dev/null

# 12. Docker disk usage (if Docker is used)
echo "Docker disk usage:"
sudo docker system df -v

# 13. Check log files specifically
echo "Large log files in /var/log:"
sudo find /var/log -type f -size +50M -exec ls -lh {} \; 2>/dev/null

# 14. Breakdown of Jenkins builds by size
echo "Breakdown of Jenkins builds by size:"
# sudo find /var/lib/jenkins/jobs -type d -name "builds" -exec du -sh {} \; 2>/dev/null | sort -hr
sudo find /var/lib/jenkins/jobs -type d -name builds -exec du -sh {} + 2>/dev/null | sort -hr | head -50


# 15. Current disk usage summary
echo "Current disk usage summary:"
df -h /