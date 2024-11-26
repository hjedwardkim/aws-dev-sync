#!/bin/bash

REMOTE_HOST="" # Replace with VM IP
REMOTE_USER="ec2-user"
LOCAL_DIR="$HOME/{project directory}"
REMOTE_DIR="/home/ec2-user/{project_directory}"
LOG_DIR="$LOCAL_DIR/dev/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to sync changes to VM
sync_to_vm() {
    rsync -avz --exclude '.git' \
              --exclude '*.pyc' \
              --exclude '__pycache__' \
              --exclude '.venv' \
              --exclude 'venv' \
              --exclude '.env' \
              --exclude .DS_Store \
              --exclude 'dev' \
              "$LOCAL_DIR/" \
              "$REMOTE_HOST:$REMOTE_DIR/"
}

# Function to fetch logs from VM
fetch_logs() {
    echo "Fetching logs from VM..."
    rsync -avz "$REMOTE_HOST:$REMOTE_DIR/dev/logs/" "$LOG_DIR/"
}

# Function to check remote logs directory for changes
check_remote_logs() {
    # Get current timestamp of remote logs directory
    REMOTE_TIMESTAMP=$(ssh "$REMOTE_USER@$REMOTE_HOST" "stat -c %Y $REMOTE_DIR/dev/logs 2>/dev/null || echo 0")
    
    # Compare with previous timestamp
    if [ -f "/tmp/remote_logs_timestamp" ]; then
        PREV_TIMESTAMP=$(cat /tmp/remote_logs_timestamp)
        if [ "$REMOTE_TIMESTAMP" != "$PREV_TIMESTAMP" ]; then
            fetch_logs
        fi
    fi
    
    # Save current timestamp
    echo "$REMOTE_TIMESTAMP" > /tmp/remote_logs_timestamp
}

# Set up remote watch using SSH
setup_remote_watch() {
    # Ensure inotifywait is installed on remote
    ssh "$REMOTE_USER@$REMOTE_HOST" "command -v inotifywait >/dev/null 2>&1 || sudo yum install -y inotify-tools"
    
    # Start remote watching in background
    ssh "$REMOTE_USER@$REMOTE_HOST" "while inotifywait -r -e modify,create,delete,move $REMOTE_DIR/dev/logs 2>/dev/null; do touch $REMOTE_DIR/dev/logs/.trigger; done" &
    REMOTE_WATCH_PID=$!
}

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    # Kill remote watch process
    ssh "$REMOTE_USER@$REMOTE_HOST" "pkill -f 'inotifywait.*$REMOTE_DIR/dev/logs'"
    exit 0
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Start remote watch
setup_remote_watch

# Main loop using fswatch for local changes
fswatch -o "$LOCAL_DIR" | while read; do
    # Ignore changes in dev/logs directory for local sync
    if ! find "$LOCAL_DIR" -path "$LOCAL_DIR/dev/logs" -prune -o -newer "$LOG_DIR" -print | grep -q .; then
        continue
    fi
    
    sync_to_vm
done &

# Periodic check for remote log changes
while true; do
    check_remote_logs
    sleep 5
done