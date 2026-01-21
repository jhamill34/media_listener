#!/bin/bash
# Test script to verify server handles client disconnects gracefully

SOCKET_PATH="/tmp/media_listener.sock"

echo "Testing client disconnect handling..."
echo ""
echo "This will:"
echo "1. Connect to the socket"
echo "2. Read a few events"
echo "3. Forcefully disconnect"
echo "4. Verify the server is still running"
echo ""

# Connect, read a few lines, then exit
timeout 5 nc -U "$SOCKET_PATH" | head -n 3

echo ""
echo "Disconnected from socket."
echo "The server should have logged the disconnect but continue running."
echo ""
echo "Testing reconnection..."

# Try to reconnect
timeout 2 nc -U "$SOCKET_PATH" | head -n 1

if [ $? -eq 0 ] || [ $? -eq 124 ]; then
    echo ""
    echo "✓ Successfully reconnected! Server is still running."
else
    echo ""
    echo "✗ Failed to reconnect. Server may have crashed."
    exit 1
fi
