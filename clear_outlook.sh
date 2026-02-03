#!/bin/zsh

# 1. Close Outlook
echo "Closing Outlook..."
osascript -e 'quit app "Microsoft Outlook"' 2>/dev/null
sleep 2
pkill -9 -x "Microsoft Outlook" 2>/dev/null

# 2. Define paths
TARGET_DIR="/Users/$USER/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile"
BACKUP_DIR="/Users/$USER/.Main_Profile_Backup"

# 3. Initial Confirmation (FORCED TO FOREGROUND)
RESPONSE=$(osascript <<EOT
    tell application "Finder"
        activate
        display dialog "The folder '$TARGET_DIR' will be moved and cleared for a new setup. Do you accept?" ¬
        buttons {"Cancel", "Accept"} ¬
        default button "Accept" ¬
        with icon note
    end tell
EOT
)

if [[ "$RESPONSE" == *"button returned:Accept"* ]]; then
    if [ -d "$TARGET_DIR" ]; then
        # Move to a hidden backup instead of Trash for easier restoration
        rm -rf "$BACKUP_DIR" 2>/dev/null
        mv "$TARGET_DIR" "$BACKUP_DIR"
        echo "Original profile backed up and removed from active folder."
        
        # 4. Reopen Outlook
        echo "Opening Outlook... please enroll your account."
        open -a "Microsoft Outlook"
        
        # 5. Wait 40 seconds
        echo "Waiting 40 seconds for account setup..."
        sleep 40
        
        # 6. Check-in with the user (FORCED TO FOREGROUND)
        FINAL_CHECK=$(osascript <<EOT
            tell application "Finder"
                activate
                display dialog "Are all your emails and folders looking good? If you select NO, your old profile will be RESTORED." ¬
                buttons {"No", "Yes"} ¬
                default button "Yes"
            end tell
EOT
)
        
        if [[ "$FINAL_CHECK" == *"button returned:Yes"* ]]; then
            # Cleanup: Move backup to Trash and empty it
            mv "$BACKUP_DIR" ~/.Trash/
            osascript -e 'tell application "Finder" to empty trash'
            echo "Success! New profile confirmed. Old files deleted."
        else
            # RESTORE LOGIC
            echo "Restoring original folder..."
            # Close Outlook again to swap folders
            osascript -e 'quit app "Microsoft Outlook"' 2>/dev/null
            sleep 2
            pkill -9 -x "Microsoft Outlook" 2>/dev/null
            
            # Remove the "new" folder and put the old one back
            rm -rf "$TARGET_DIR"
            mv "$BACKUP_DIR" "$TARGET_DIR"
            
            echo "Restore complete. Your original 'Main Profile' is back in place."
            open -a "Microsoft Outlook"
        fi
    else
        echo "Folder not found: $TARGET_DIR"
    fi
else
    echo "Canceled by user."
fi
