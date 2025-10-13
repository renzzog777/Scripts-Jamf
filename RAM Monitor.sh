#!/bin/bash

# --- Configuration ---
OUTPUT_FILE=~/Desktop/System_Monitor_Log.txt
STOP_FILE=~/Desktop/.monitor_stop_signal

# --- Cleanup Function ---
cleanup() {
  rm -f "$STOP_FILE"
  echo -e "\nMonitoring stopped. Data saved to $OUTPUT_FILE"
}
trap cleanup EXIT

# --- Function to get USED RAM in GB ---
get_ram_usage() {
  top -l 1 | grep PhysMem | awk '{print $2}' | sed 's/[^0-9.]*//g'
}

# --- Function to get process count ---
get_process_count() {
  sysctl -n kern.nprocs
}

# --- Function to get top 5 process names (Shortened) ---
get_top_processes() {
  ##-- FINAL FIX: Manually shortening the process path --##
  
  # 1. Get the top 5 processes sorted by memory.
  # 2. Use 'awk' to isolate just the command path from each line.
  # 3. Loop through the paths and use 'basename' to get just the final name.
  # 4. Format the final list.
  ps ax -o pmem,command | tail -n +2 | sort -rn | head -n 5 | awk '{print $2}' | while read -r path; do
    basename "$path"
  done | tr '\n' ';'
}

# --- Monitor Loop Function ---
monitor_loop() {
  if [ ! -f "$OUTPUT_FILE" ]; then
    echo -e "Timestamp\tUsed_RAM_MB\tTotal_Processes\tTop_Processes_by_RAM" > "$OUTPUT_FILE"
  fi

  while [ ! -f "$STOP_FILE" ]; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    RAM_USED=$(get_ram_usage)
    PROCESS_COUNT=$(get_process_count)
    TOP_PROCESSES=$(get_top_processes)

    echo "Logging: $TIMESTAMP | Used RAM: ${RAM_USED}G | Processes: $PROCESS_COUNT"
    echo -e "$TIMESTAMP\t$RAM_USED\t$PROCESS_COUNT\t$TOP_PROCESSES" >> "$OUTPUT_FILE"

    sleep 5
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