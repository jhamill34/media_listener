#!/bin/bash
# Watch for track changes only

SOCKET_PATH="/tmp/media_listener.sock"

echo "Watching for track changes..."
echo ""

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for this script"
    exit 1
fi

nc -U "$SOCKET_PATH" | while IFS= read -r line; do
    # Only show events where track_changed is true
    echo "$line" | jq -e '.track_changed == true' > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "$line" | jq -r '
            "🎵 [\(.app_name)] \(.track_info.title // "Unknown") - \(.track_info.artist // "Unknown")"
        '
    fi
done
