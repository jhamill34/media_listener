#!/usr/bin/env python3
"""
Example client for consuming media events from media_listener UNIX socket.
"""

import socket
import json
import sys

SOCKET_PATH = "/tmp/media_listener.sock"

def main():
    print(f"Connecting to {SOCKET_PATH}...")

    # Create UNIX socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        sock.connect(SOCKET_PATH)
        print("Connected! Listening for media events...\n")

        buffer = ""
        while True:
            # Receive data
            data = sock.recv(4096)
            if not data:
                print("Connection closed by server")
                break

            # Decode and add to buffer
            buffer += data.decode('utf-8')

            # Process complete JSON objects (newline-delimited)
            while '\n' in buffer:
                line, buffer = buffer.split('\n', 1)
                if line.strip():
                    try:
                        event = json.loads(line)
                        print_event(event)
                    except json.JSONDecodeError as e:
                        print(f"Error parsing JSON: {e}")
                        print(f"Raw data: {line}")

    except FileNotFoundError:
        print(f"Error: Socket {SOCKET_PATH} not found")
        print("Make sure media_listener is running")
        sys.exit(1)
    except ConnectionRefusedError:
        print(f"Error: Connection refused to {SOCKET_PATH}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nDisconnecting...")
    finally:
        sock.close()

def print_event(event):
    """Pretty print a media event"""
    event_type = event.get('event_type', 'unknown')

    print("═" * 60)
    print(f"Event: {event_type.upper()}")
    print(f"Timestamp: {event.get('timestamp', 'N/A')}")

    if event_type == 'now_playing_info_changed':
        print(f"Event #: {event.get('event_number', 'N/A')}")
        print(f"App: {event.get('app_name', 'Unknown')}")
        print(f"State: {event.get('playback_state', 'Unknown')}")

        if event.get('track_changed'):
            print("🎵 TRACK CHANGED")

        track_info = event.get('track_info', {})
        if track_info:
            print("\nTrack Info:")
            if 'title' in track_info:
                print(f"  Title: {track_info['title']}")
            if 'artist' in track_info:
                print(f"  Artist: {track_info['artist']}")
            if 'album' in track_info:
                print(f"  Album: {track_info['album']}")
            if 'duration' in track_info:
                duration = track_info['duration']
                minutes = int(duration // 60)
                seconds = int(duration % 60)
                print(f"  Duration: {minutes}:{seconds:02d}")
            if 'elapsed' in track_info:
                elapsed = track_info['elapsed']
                minutes = int(elapsed // 60)
                seconds = int(elapsed % 60)
                print(f"  Elapsed: {minutes}:{seconds:02d}")

    elif event_type == 'application_changed':
        print(f"New App: {event.get('app_name', 'Unknown')}")
        print(f"State: {event.get('playback_state', 'Unknown')}")

    print()

if __name__ == '__main__':
    main()
