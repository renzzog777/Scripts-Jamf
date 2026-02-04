#!/zsh

# --- 1. SETTINGS & PATHS ---
currentUser=$(stat -f "%Su" /dev/console)
currentUserID=$(id -u "$currentUser")
TARGET_DIR="/Users/$currentUser/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile"
BACKUP_DIR="/Users/$currentUser/.Main_Profile_Backup"
JH="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# --- 2. PROMOTE USER TO ADMIN (TEMP) ---
# Grants admin rights so the user can perform system-level tasks if needed
/usr/sbin/dseditgroup -o edit -a "$currentUser" -t user admin

# Create the 15-minute removal timer (Launch Daemon)
defaults write /Library/LaunchDaemons/removeAdmin.plist Label -string "removeAdmin"
defaults write /Library/LaunchDaemons/removeAdmin.plist ProgramArguments -array -string /bin/sh -string "/Library/Application Support/JAMF/removeAdminRights.sh"
defaults write /Library/LaunchDaemons/removeAdmin.plist StartInterval -integer 900
defaults write /Library/LaunchDaemons/removeAdmin.plist RunAtLoad -boolean yes
chown root:wheel /Library/LaunchDaemons/removeAdmin.plist
chmod 644 /Library/LaunchDaemons/removeAdmin.plist
launchctl load /Library/LaunchDaemons/removeAdmin.plist

# Create the background cleanup script
mkdir -p /private/var/userToRemove
echo "$currentUser" > /private/var/userToRemove/user

cat << EOF > /Library/Application\ Support/JAMF/removeAdminRights.sh
#!/bin/bash
userToRemove=\$(cat /private/var/userToRemove/user)
/usr/sbin/dseditgroup -o edit -d \$userToRemove -t user admin
rm -f /private/var/userToRemove/user
launchctl unload /Library/LaunchDaemons/removeAdmin.plist
rm /Library/LaunchDaemons/removeAdmin.plist
EOF
chmod +x /Library/Application\ Support/JAMF/removeAdminRights.sh

# --- 3. CLOSE OUTLOOK ---
/bin/launchctl asuser "$currentUserID" osascript -e 'quit app "Microsoft Outlook"' 2>/dev/null
sleep 2
pkill -9 -x "Microsoft Outlook" 2>/dev/null

# --- 4. INITIAL CONFIRMATION ---
RESPONSE=$("/bin/launchctl" asuser "$currentUserID" "$JH" \
-windowType utility \
-title "Maintenance Required" \
-heading "Free Up Disk Space" \
-description "Outlook will be reset to free up space. Your old data will be backed up temporarily. You have Admin rights for 15 minutes. Proceed?" \
-button1 "Accept" \
-button2 "Cancel" \
-defaultButton 1)

if [ "$RESPONSE" = "0" ]; then 
    if [ -d "$TARGET_DIR" ]; then
        # Move to hidden backup (No space saved yet)
        rm -rf "$BACKUP_DIR" 2>/dev/null
        mv "$TARGET_DIR" "$BACKUP_DIR"
        
        # Reopen Outlook for the user to enroll
        /bin/launchctl asuser "$currentUserID" open -a "Microsoft Outlook"
        
        echo "Waiting 40 seconds for account setup..."
        sleep 40
        
        # --- 5. FINAL CHECK & SPACE RECLAMATION ---
        FINAL_CHECK=$("/bin/launchctl" asuser "$currentUserID" "$JH" \
        -windowType utility \
        -title "Verification" \
        -description "Is Outlook working correctly? Selecting YES will PERMANENTLY DELETE the old backup and free up space." \
        -button1 "Yes" \
        -button2 "No" \
        -defaultButton 1)
        
        if [ "$FINAL_CHECK" = "0" ]; then
            # EFFICIENT LOGIC: Immediate deletion bypasses Trash and frees space now
            rm -rf "$BACKUP_DIR"
            /bin/launchctl asuser "$currentUserID" "$JH" -windowType utility -description "Success! Space has been reclaimed." -button1 "OK"
        else
            # RESTORE LOGIC (If user says No)
            /bin/launchctl asuser "$currentUserID" osascript -e 'quit app "Microsoft Outlook"' 2>/dev/null
            sleep 2
            pkill -9 -x "Microsoft Outlook" 2>/dev/null
            rm -rf "$TARGET_DIR"
            mv "$BACKUP_DIR" "$TARGET_DIR"
            /bin/launchctl asuser "$currentUserID" open -a "Microsoft Outlook"
            echo "Profile restored. No space was freed."
        fi
    fi
else
    echo "Canceled by user."
fi

exit 0
