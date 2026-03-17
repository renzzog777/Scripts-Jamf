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
BACKUP_BASE="/Users/$currentUser/.Outlook_Backup_Data"

# --- [STEP 2: USER INTERACTION & BACKUP] ---
echo "--- [PHASE 2: USER CONSENT & BACKUP] ---"
RESPONSE=$("$JH" -windowType utility -title "IT Maintenance" -heading "Outlook Disk Cleanup" \
-description "Outlook will be reset to free up disk space. Your data will be backed up temporarily. Proceed?" \
-button1 "Accept" -button2 "Cancel" -defaultButton 1 -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarUtilitiesFolderIcon.icns)

if [[ "$RESPONSE" != "0" ]]; then
    echo "Status: CANCELLED. User opted out of maintenance."
    exit 0
fi

echo "Action: Closing Outlook and creating temporary backup..."
/usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
/bin/sleep 2

/bin/mkdir -p "$BACKUP_BASE"
/usr/sbin/chown "$currentUser" "$BACKUP_BASE"

if [[ -d "$newOutlookPath" ]]; then
    /bin/mv "$newOutlookPath" "$BACKUP_BASE/Profiles_Backup"
    echo "Status: SUCCESS. Profiles moved to $BACKUP_BASE."
fi

/usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"

# --- [STEP 3: VERIFICATION & PURGE] ---
echo "--- [PHASE 3: VERIFICATION & DATA PURGE] ---"
FINAL_CHECK=$("$JH" -windowType utility -title "Verification" \
-description "Is Outlook working correctly? 

Selecting YES will PERMANENTLY delete your old data to save space. 
Selecting NO will restore your previous data immediately." \
-button1 "Yes" -button2 "No" -defaultButton 1)

if [[ "$FINAL_CHECK" == "0" ]]; then
    echo "Action: User confirmed success. Calculating space savings..."
    
    if [[ -d "$BACKUP_BASE/Profiles_Backup" ]]; then
        RECLAIMED_SIZE=$(du -sh "$BACKUP_BASE/Profiles_Backup" | awk '{print $1}')
    else
        RECLAIMED_SIZE="0B"
    fi

    /bin/rm -rf "$BACKUP_BASE"

    echo "--- Purge Results ---"
    echo "Status: SUCCESS. Outlook cache permanently removed."
    echo "Summary: Reclaimed $RECLAIMED_SIZE of disk space."
    
else
    echo "Action: User reported issue. Restoring data..."
    /usr/bin/pkill -u "$currentUser" -x "Microsoft Outlook"
    /bin/sleep 2
    /bin/rm -rf "$newOutlookPath"

    if [[ -d "$BACKUP_BASE/Profiles_Backup" ]]; then
        /bin/mv "$BACKUP_BASE/Profiles_Backup" "$newOutlookPath"
        echo "Status: RESTORED. Original data returned to library."
    fi

    /usr/sbin/chown -R "$currentUser" "$outlookRoot"
    /usr/bin/sudo -u "$currentUser" /usr/bin/open -a "Microsoft Outlook"
fi

# --- [STEP 4: FINALIZATION & INVENTORY] ---
echo "--- [PHASE 4: INVENTORY UPDATE & CLEANUP] ---"
echo "Action: Updating Jamf Inventory to clear local storage alerts..."
/usr/local/bin/jamf recon
echo "Status: COMPLETE. Inventory updated at $(date)."

exit 0
