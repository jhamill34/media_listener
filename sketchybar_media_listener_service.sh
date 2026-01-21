#!/bin/bash
# Simple one-line format for each event

SOCKET_PATH="/tmp/media_listener.sock"

echo "Monitoring media events (simple format)..."
echo ""

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for this script"
    exit 1
fi

send () 
{
    line="$1"

    sketchybar --trigger custom_media_change MEDIA_INFO="$line"

    echo "$line" | jq 
}

nc -U "$SOCKET_PATH" | while IFS= read -r line; do
    event_type=$(echo "$line" | jq -r '.event_type')
    case "$event_type" in 
        "now_playing_info_changed"|"current_state")
            send "$line"
            ;;

    esac
done
