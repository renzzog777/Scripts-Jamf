#!/bin/bash

# --- Configuration ---
OUTPUT_TXT_FILE=~/Desktop/System_Monitor_Log.txt
OUTPUT_CSV_FILE=~/Desktop/System_Monitor_Log.csv
STOP_FILE=~/Desktop/.monitor_stop_signal

# --- Calculate Total System RAM (once for efficiency) ---
TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
TOTAL_RAM_MB=$((TOTAL_RAM_BYTES / 1024 / 1024))

# --- Cleanup Function ---
cleanup() {
  rm -f "$STOP_FILE"
  echo -e "\nMonitoring stopped. Data saved to log files."
}
trap cleanup EXIT

# --- Function to get FREE RAM in MB ---
get_free_ram() {
  # Gets free memory pages from the kernel and converts to Megabytes.
  PAGE_SIZE=$(sysctl -n hw.pagesize)
  FREE_PAGES=$(vm_stat | grep "Pages free:" | awk '{print $3}' | tr -d '.')
  FREE_BYTES=$((FREE_PAGES * PAGE_SIZE))
  FREE_MB=$((FREE_BYTES / 1024 / 1024))
  echo $FREE_MB
}

# --- Function to get process count ---
get_process_count() {
  sysctl -n kern.nprocs
}

# --- Function to get top 5 process names (Shortened) ---
get_top_processes() {
  # Gets top 5 processes by memory, then shortens the path to just the name.
  ps ax -o pmem,command | tail -n +2 | sort -rn | head -n 5 | awk '{print $2}' | while read -r path; do
    basename "$path"
  done | tr '\n' ';'
}

# --- Monitor Loop Function ---
monitor_loop() {
  # Create headers for both files if they don't exist
  if [ ! -f "$OUTPUT_TXT_FILE" ]; then
    echo -e "Timestamp\tUsed_RAM_MB\tFree_RAM_MB\tUsed_RAM_%\tFree_RAM_%\tTotal_Processes\tTop_Processes_by_RAM" > "$OUTPUT_TXT_FILE"
    echo "Timestamp,Used_RAM_MB,Free_RAM_MB,Used_RAM_%,Free_RAM_%,Total_Processes,Top_Processes_by_RAM" > "$OUTPUT_CSV_FILE"
  fi

  while [ ! -f "$STOP_FILE" ]; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    
    RAM_FREE=$(get_free_ram)
    RAM_USED=$((TOTAL_RAM_MB - RAM_FREE))
    
    ##-- FIX: Increased precision and added proper rounding --##
    # Calculate with high precision, then use printf to round to the nearest whole number.
    PERCENT_USED=$(echo "scale=4; ($RAM_USED / $TOTAL_RAM_MB) * 100" | bc | xargs printf "%.0f")
    PERCENT_FREE=$(echo "scale=4; ($RAM_FREE / $TOTAL_RAM_MB) * 100" | bc | xargs printf "%.0f")
    
    PROCESS_COUNT=$(get_process_count)
    TOP_PROCESSES=$(get_top_processes)

    echo "Logging: $TIMESTAMP | Used: ${RAM_USED}MB (${PERCENT_USED}%) | Free: ${RAM_FREE}MB (${PERCENT_FREE}%)"
    
    # Write to the tab-separated TXT file
    echo -e "$TIMESTAMP\t$RAM_USED\t$RAM_FREE\t$PERCENT_USED\t$PERCENT_FREE\t$PROCESS_COUNT\t$TOP_PROCESSES" >> "$OUTPUT_TXT_FILE"
    
    # Write to the comma-separated CSV file
    echo "$TIMESTAMP,$RAM_USED,$RAM_FREE,$PERCENT_USED,$PERCENT_FREE,$PROCESS_COUNT,\"$TOP_PROCESSES\"" >> "$OUTPUT_CSV_FILE"

    sleep 0.8
  done
}

# --- Main Execution ---
echo "--- Starting System Monitor ---"
echo "A control window will appear. Click 'STOP' in that window to end the script."

monitor_loop &
MONITOR_PID=$!

osascript -e 'display dialog "Monitoring is active. Click STOP to end." with title "System Monitor" buttons {"STOP"} default button "STOP" with icon caution'

echo "Stop signal received. Terminating monitor process..."
kill $MONITOR_PID

exit 0
