#!/bin/zsh

# --- 1. ENVIRONMENT SETUP ---
LOG_FILE="/var/log/outlook_cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting Outlook Cleanup: $(date) ---"

# Get current user details
currentUser=$(/usr/bin/stat -f "%Su" /dev/console)
currentUserID=$(/usr/bin/id -u "$currentUser")
# Path to jamfHelper
JH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Verify we aren't running as 'root' at the console (login window)
if [[ "$currentUser" == "root" || -z "$currentUser" ]]; then
    echo "Error: No user logged in. Exiting."
    exit 1
fi

# Define paths
legacyPath="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile"
newOutlookPath="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles"
BACKUP_BASE="/Users/$currentUser/.Outlook_Backup_Data"

# --- 2. USER INTERACTION ---
echo "Asking user for permission..."
RESPONSE=$("$JH" -windowType utility -title "IT Maintenance" -heading "Outlook Disk Cleanup" \
-description "Outlook needs to be reset to free up disk space. Your data will be backed up temporarily. Proceed?" \
-button1 "Accept" -button2 "Cancel" -defaultButton 1 -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarUtilitiesFolderIcon.icns)

if [ "$RESPONSE" != "0" ]; then
    echo "User cancelled or timed out. Exiting."
    exit 0
fi

# --- 3. THE WORK ---
echo "Closing Outlook..."
/usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
/bin/sleep 2

# Create backup directory
/bin/mkdir -p "$BACKUP_BASE"
/usr/sbin/chown "$currentUser" "$BACKUP_BASE"

# Move Data (Running as root, so no permission issues)
if [[ -d "$legacyPath" ]]; then
    /bin/mv "$legacyPath" "$BACKUP_BASE/Legacy_Backup"
    echo "Legacy profile backed up."
fi

if [[ -d "$newOutlookPath" ]]; then
    /bin/mv "$newOutlookPath" "$BACKUP_BASE/New_Backup"
    echo "New Outlook data backed up."
fi

# Reopen Outlook as the user
echo "Reopening Outlook..."
/usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"

# Verification Dialog
FINAL_CHECK=$("$JH" -windowType utility -title "Verification" \
-description "Is Outlook working? Clicking YES will permanently delete the old cached data to save space." \
-button1 "Yes" -button2 "No" -defaultButton 1)

if [ "$FINAL_CHECK" = "0" ]; then
    echo "User confirmed. Deleting backup..."
    /bin/rm -rf "$BACKUP_BASE"
    echo "Space reclaimed successfully."
else
    echo "User reported issue. Reverting..."
    /usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
    /bin/sleep 2
    /bin/rm -rf "$legacyPath" "$newOutlookPath"
    [[ -d "$BACKUP_BASE/Legacy_Backup" ]] && /bin/mv "$BACKUP_BASE/Legacy_Backup" "$legacyPath"
    [[ -d "$BACKUP_BASE/New_Backup" ]] && /bin/mv "$BACKUP_BASE/New_Backup" "$newOutlookPath"
    /usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"
fi

echo "--- Task Finished: $(date) ---"
exit 0
