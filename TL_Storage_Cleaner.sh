#!/bin/zsh

# --- [STEP 1: INITIALIZATION] ---
echo "--- [PHASE 1: ENVIRONMENT SETUP] ---"
LOG_FILE="/var/log/outlook_cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Verification: Logic check started at $(date)"

# Identify the logged-in user
currentUser=$(/usr/bin/stat -f "%Su" /dev/console)
currentUserID=$(/usr/bin/id -u "$currentUser")
JH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Safety Check
if [[ "$currentUser" == "root" || -z "$currentUser" ]]; then
    echo "Status: ERROR. No user session detected. Aborting safely."
    exit 0
fi

# Define Paths
outlookRoot="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook"
newOutlookPath="$outlookRoot/Outlook 15 Profiles"
legacyProfilePath="$newOutlookPath/Main Profile"
BACKUP_BASE="/Users/$currentUser/.Outlook_Backup_Data"
BACKUP_FOLDER="$BACKUP_BASE/Profiles_Backup"

# --- [STEP 2: USER INTERACTION & BACKUP] ---
echo "--- [PHASE 2: USER CONSENT & BACKUP] ---"
RESPONSE=$("$JH" -windowType utility -title "IT Maintenance" -heading "Outlook Disk Cleanup" \
-description "Outlook will be reset to free up disk space. Your data will be backed up temporarily. Proceed?" \
-button1 "Accept" -button2 "Cancel" -defaultButton 1 -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarUtilitiesFolderIcon.icns)

if [[ "$RESPONSE" != "0" ]]; then
    echo "Status: CANCELLED. User opted out."
    exit 0
fi

echo "Action: Closing Outlook and creating backup..."
/usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
/bin/sleep 2

# Clean start for backup directory
/bin/rm -rf "$BACKUP_BASE"
/bin/mkdir -p "$BACKUP_BASE"
/usr/sbin/chown "$currentUser" "$BACKUP_BASE"

if [[ -d "$newOutlookPath" ]]; then
    # Move the folder to the backup location
    /bin/mv "$newOutlookPath" "$BACKUP_FOLDER"
    echo "Status: SUCCESS. Profiles moved to $BACKUP_FOLDER."
fi

# BUG FIX: Pre-create the Skeleton 'Main Profile' so Outlook launches correctly
echo "Action: Pre-creating Main Profile skeleton..."
/bin/mkdir -p "$legacyProfilePath"
/usr/sbin/chown -R "$currentUser" "$newOutlookPath"

# Reopen for testing
/usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"

# --- [STEP 3: VERIFICATION & PURGE] ---
echo "--- [PHASE 3: VERIFICATION & DATA PURGE] ---"
FINAL_CHECK=$("$JH" -windowType utility -title "Verification" \
-description "Is Outlook working correctly? 

Selecting YES will PERMANENTLY delete your old data. 
Selecting NO will restore your previous data immediately." \
-button1 "Yes" -button2 "No" -defaultButton 1)

if [[ "$FINAL_CHECK" == "0" ]]; then
    echo "Action: User confirmed success. Calculating space savings..."
    
    if [[ -d "$BACKUP_FOLDER" ]]; then
        RECLAIMED_SIZE=$(du -sh "$BACKUP_FOLDER" | awk '{print $1}')
    else
        RECLAIMED_SIZE="0B"
    fi

    /bin/rm -rf "$BACKUP_BASE"

    echo "--- Purge Results ---"
    echo "Status: SUCCESS. Outlook cache purged."
    echo "Summary: Reclaimed $RECLAIMED_SIZE."
    
else
    echo "Action: User reported issue. Starting SURGICAL RESTORE..."
    /usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
    /bin/sleep 2
    
    # CRITICAL FIX: We MUST delete the 'Outlook 15 Profiles' folder entirely 
    # so the 'mv' command renames the backup folder instead of dropping it inside.
    /bin/rm -rf "$newOutlookPath"

    if [[ -d "$BACKUP_FOLDER" ]]; then
        # Move the backup back to the original name
        /bin/mv "$BACKUP_FOLDER" "$newOutlookPath"
        echo "Status: RESTORED. Original data replaced the skeleton."
    else
        echo "Status: FAILED. No backup found to restore."
    fi

    # Ensure user ownership
    /usr/sbin/chown -R "$currentUser" "$outlookRoot"
    /usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"
fi

# --- [STEP 4: FINALIZATION & INVENTORY] ---
echo "--- [PHASE 4: INVENTORY UPDATE] ---"
echo "Action: Updating Jamf Inventory..."
/usr/local/bin/jamf recon
echo "Status: COMPLETE. Task finished at $(date)."

exit 0
