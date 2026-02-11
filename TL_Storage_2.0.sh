#!/bin/zsh

# --- 1. ROOT & USER VALIDATION ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root via Jamf."
   exit 1
fi

# Set up logging to local file and Jamf Pro Policy Logs
LOG_FILE="/var/log/outlook_cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Starting Dual-Version Outlook Cleanup: $(date) ---"

# Identify the specific person at the keys
currentUser=$(/usr/bin/stat -f "%Su" /dev/console)
currentUserID=$(/usr/bin/id -u "$currentUser")
JH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Check if user is already an admin (Safety for service accounts/IT)
isAlreadyAdmin=$(/usr/bin/groups "$currentUser" | /usr/bin/grep -w admin)

# --- 2. SURGICAL ADMIN PROMOTION ---
if [[ -z "$isAlreadyAdmin" ]]; then
    echo "$(date): Temporarily promoting $currentUser to admin..."
    /usr/sbin/dseditgroup -o edit -a "$currentUser" -t user admin
else
    echo "$(date): $currentUser is already an admin. No promotion needed."
fi

# Define paths for both Legacy and New Outlook
legacyPath="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile"
newOutlookPath="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles"
BACKUP_BASE="/Users/$currentUser/.Outlook_Backup_Data"

# --- 3. THE WORK: OUTLOOK CLEANUP ---
echo "$(date): Closing Outlook for $currentUser..."
/usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook" 2>/dev/null
/bin/sleep 2

RESPONSE=$("/bin/launchctl" asuser "$currentUserID" "$JH" \
-windowType utility -title "Maintenance" -heading "Disk Cleanup" \
-description "Outlook will be reset to free up space. All profile versions detected will be cleared. You have temporary admin rights. Proceed?" \
-button1 "Accept" -button2 "Cancel" -defaultButton 1)

if [ "$RESPONSE" = "0" ]; then 
    echo "$(date): User accepted. Cleaning up backup directory..."
    /bin/rm -rf "$BACKUP_BASE" 2>/dev/null
    /bin/mkdir -p "$BACKUP_BASE"

    # Move any existing profile data to backup
    [[ -d "$legacyPath" ]] && /bin/mv "$legacyPath" "$BACKUP_BASE/Legacy_Backup" && echo "$(date): Legacy profile backed up."
    [[ -d "$newOutlookPath" ]] && /bin/mv "$newOutlookPath" "$BACKUP_BASE/New_Backup" && echo "$(date): New Outlook data backed up."
    
    # Reopen Outlook
    /bin/launchctl asuser "$currentUserID" /usr/bin/open -a "Microsoft Outlook"

    # Wait for Outlook to recreate a profile directory
    TIMEOUT=0
    echo "$(date): Waiting for Outlook to initialize new profile..."
    while [[ ! -d "$legacyPath" && ! -d "$newOutlookPath" && $TIMEOUT -lt 30 ]]; do
        /bin/sleep 2
        ((TIMEOUT++))
    done

    FINAL_CHECK=$("/bin/launchctl" asuser "$currentUserID" "$JH" \
    -windowType utility -title "Verification" \
    -description "Is Outlook working correctly? Selecting YES will PERMANENTLY DELETE all backups to free space." \
    -button1 "Yes" -button2 "No" -defaultButton 1)
    
    if [ "$FINAL_CHECK" = "0" ]; then
        echo "$(date): User confirmed success. Reclaiming space..."
        /bin/rm -rf "$BACKUP_BASE"
        echo "$(date): Space successfully reclaimed."
    else
        echo "$(date): User reported issue. Restoring all profiles..."
        /usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
        /bin/sleep 2
        /bin/rm -rf "$legacyPath" "$newOutlookPath" 2>/dev/null
        
        [[ -d "$BACKUP_BASE/Legacy_Backup" ]] && /bin/mv "$BACKUP_BASE/Legacy_Backup" "$legacyPath"
        [[ -d "$BACKUP_BASE/New_Backup" ]] && /bin/mv "$BACKUP_BASE/New_Backup" "$newOutlookPath"
        
        /bin/launchctl asuser "$currentUserID" /usr/bin/open -a "Microsoft Outlook"
        echo "$(date): Restore complete."
    fi
else
    echo "$(date): User canceled the operation."
fi

# --- 4. THE CLEANUP: DEMOTE FROM ADMIN ---
if [[ -z "$isAlreadyAdmin" ]]; then
    echo "$(date): Removing temporary admin rights from $currentUser..."
    /usr/sbin/dseditgroup -o edit -d "$currentUser" -t user admin
fi

echo "--- Task Finished: $(date) ---"
exit 0
