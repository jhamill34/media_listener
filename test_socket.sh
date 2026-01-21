#!/bin/bash
# Socket test script with jq parsing

SOCKET_PATH="/tmp/media_listener.sock"

echo "Testing socket connection to $SOCKET_PATH"
echo "Parsing JSON events with jq..."
echo "Press Ctrl+C to stop"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Warning: jq not found, falling back to raw output"
    nc -U "$SOCKET_PATH"
    exit 0
fi

# Read from socket line by line and parse with jq
nc -U "$SOCKET_PATH" | while IFS= read -r line; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Parse and pretty-print the JSON
    echo "$line" | jq -C '
        if .event_type == "now_playing_info_changed" then
            "[\(.event_number)] \(.event_type | ascii_upcase)",
            "App: \(.app_name)",
            "State: \(.playback_state)",
            (if .track_changed then "🎵 TRACK CHANGED" else empty end),
            (if .track_info then
                "\nTrack Info:",
                (if .track_info.title then "  Title: \(.track_info.title)" else empty end),
                (if .track_info.artist then "  Artist: \(.track_info.artist)" else empty end),
                (if .track_info.album then "  Album: \(.track_info.album)" else empty end),
                (if .track_info.duration then "  Duration: \(.track_info.duration)s" else empty end),
                (if .track_info.elapsed then "  Elapsed: \(.track_info.elapsed)s" else empty end)
            else empty end)
        elif .event_type == "application_changed" then
            "\(.event_type | ascii_upcase)",
            "App: \(.app_name)",
            "State: \(.playback_state)"
        else
            .
        end
    ' -r

    echo ""
done
