#!/bin/bash

# extract_logs.sh
# Script to extract NeewerLite logs from unified logging system

# Configuration
APP_SUBSYSTEM="com.neewerlite.app"
OUTPUT_DIR="$HOME/Desktop/NeewerLite_Logs"
DEFAULT_HOURS="24"

# Parse command line arguments
HOURS=${1:-$DEFAULT_HOURS}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate filename with timestamp
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
OUTPUT_FILE="$OUTPUT_DIR/neewerlite_logs_$TIMESTAMP.txt"

echo "Extracting NeewerLite logs from the last $HOURS hours..."
echo "Output file: $OUTPUT_FILE"

# Extract logs
log show \
    --predicate "subsystem == '$APP_SUBSYSTEM'" \
    --last "${HOURS}h" \
    --style compact \
    --info \
    --debug > "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Logs extracted successfully!"
    echo "📁 File location: $OUTPUT_FILE"
    echo "📊 Log entries: $(wc -l < "$OUTPUT_FILE")"
    
    # Open the file in the default text editor
    read -p "Open the log file? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "$OUTPUT_FILE"
    fi
else
    echo "❌ Failed to extract logs"
    exit 1
fi

# Optional: Clean up old log files (keep only last 10)
cd "$OUTPUT_DIR"
ls -t neewerlite_logs_*.txt | tail -n +11 | xargs rm -f 2>/dev/null

echo "🧹 Cleaned up old log files (keeping last 10)"
