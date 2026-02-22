find / -type f -path "*/.git/config" 2>/dev/null -exec grep -Eo 'url *= *https?://[^[:space:]]+:[^[:space:]@]+@[^[:space:]]+' {} \;
