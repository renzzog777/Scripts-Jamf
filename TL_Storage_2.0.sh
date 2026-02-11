#!/bin/zsh

# --- 1. SETUP & LOGGING ---
LOG_FILE="/var/log/outlook_cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting Outlook Cleanup: $(date) ---"

# Identity Check
currentUser=$(/usr/bin/stat -f "%Su" /dev/console)
currentUserID=$(/usr/bin/id -u "$currentUser")
JH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

if [[ "$currentUser" == "root" ]]; then
    echo "Error: Running at login window or no user logged in."
    exit 1
fi

# Define Paths
outlookRoot="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook"
legacyPath="$outlookRoot/Outlook 15 Profiles/Main Profile"
newOutlookPath="$outlookRoot/Outlook 15 Profiles"
BACKUP_BASE="/Users/$currentUser/.Outlook_Backup_Data"

# --- 2. USER CONSENT ---
RESPONSE=$("$JH" -windowType utility -title "Maintenance" -heading "Outlook Cleanup" \
-description "This will reset Outlook to save space. Your data will be backed up. Proceed?" \
-button1 "Accept" -button2 "Cancel" -defaultButton 1)

if [[ "$RESPONSE" != "0" ]]; then
    echo "User cancelled."
    exit 0
fi

# --- 3. EXECUTION ---
/usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
/bin/sleep 2

# Create Backup
/bin/mkdir -p "$BACKUP_BASE"

if [[ -d "$legacyPath" ]]; then
    /bin/mv "$legacyPath" "$BACKUP_BASE/Legacy_Backup"
    echo "Legacy data moved to backup."
fi

# Note: Moving the whole 'Profiles' folder for New Outlook
if [[ -d "$newOutlookPath" ]]; then
    /bin/mv "$newOutlookPath" "$BACKUP_BASE/New_Backup"
    echo "New Outlook data moved to backup."
fi

# Open Outlook to let it generate fresh (empty) files
/usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"

# --- 4. VERIFICATION & RESTORE ---
FINAL_CHECK=$("$JH" -windowType utility -title "Verification" \
-description "Is Outlook working? 'YES' deletes backups forever. 'NO' restores your old data." \
-button1 "Yes" -button2 "No" -defaultButton 1)

if [[ "$FINAL_CHECK" == "0" ]]; then
    echo "Cleanup confirmed. Deleting backup..."
    /bin/rm -rf "$BACKUP_BASE"
else
    echo "Issue reported. Starting Restore..."
    /usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
    /bin/sleep 2

    # CRITICAL: Remove the NEW empty folders before moving the OLD ones back
    /bin/rm -rf "$legacyPath"
    /bin/rm -rf "$newOutlookPath"

    # Restore Legacy
    if [[ -d "$BACKUP_BASE/Legacy_Backup" ]]; then
        /bin/mkdir -p "$(dirname "$legacyPath")"
        /bin/mv "$BACKUP_BASE/Legacy_Backup" "$legacyPath"
    fi

    # Restore New Outlook
    if [[ -d "$BACKUP_BASE/New_Backup" ]]; then
        /bin/mkdir -p "$(dirname "$newOutlookPath")"
        /bin/mv "$BACKUP_BASE/New_Backup" "$newOutlookPath"
    fi

    # FIX PERMISSIONS: Ensure the user owns the restored files
    /usr/sbin/chown -R "$currentUser" "$outlookRoot"
    
    /usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"
    echo "Restore complete."
fi

echo "--- Finished: $(date) ---"
exit 0
