# Socket API Documentation

## Overview

`media_listener` publishes real-time media events over a UNIX domain socket at `/tmp/media_listener.sock`.

Events are sent as newline-delimited JSON objects, making it easy to consume from any programming language.

## Connection

```bash
# Using netcat
nc -U /tmp/media_listener.sock

# Using Python
python3 example_client.py

# Using any language with socket support
socket = connect_to("/tmp/media_listener.sock")
```

## Event Format

All events are JSON objects with the following common fields:

- `event_type` (string): Type of event ("now_playing_info_changed", "application_changed", or "current_state")
- `timestamp` (number): Unix timestamp when event occurred

### Event Type: `current_state`

Sent when a client first connects and periodically (every 5 seconds by default).

**Fields:**
```json
{
  "event_type": "current_state",
  "timestamp": 1737496543.789,
  "app_name": "Spotify",
  "app_pid": 12345,
  "playback_state": "playing",
  "track_info": {
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Name",
    "duration": 240.5,
    "elapsed": 35.2,
    "playback_rate": 1.0
  }
}
```

**When Sent:**
- Immediately when a new client connects (so clients always have initial state)
- Every 5 seconds to all connected clients (periodic updates)

### Event Type: `now_playing_info_changed`

Sent when media playback info changes (track change, play/pause, etc.)

**Fields:**
```json
{
  "event_type": "now_playing_info_changed",
  "timestamp": 1737496543.123,
  "event_number": 42,
  "track_changed": true,
  "app_name": "Spotify",
  "app_pid": 12345,
  "playback_state": "playing",
  "playback_state_code": 1,
  "track_info": {
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Name",
    "duration": 240.5,
    "elapsed": 30.2,
    "playback_rate": 1.0
  }
}
```

**Field Details:**
- `event_number`: Sequential counter for all events
- `track_changed`: Boolean indicating if this is a new track
- `app_name`: Name of the media application (e.g., "Spotify", "Google Chrome")
- `app_pid`: Process ID of the application (optional)
- `playback_state`: One of "playing", "paused", "stopped"
- `playback_state_code`: Raw playback state code (1=playing, 2=paused, 3=stopped)
- `track_info`: Object containing track metadata (all fields optional)
  - `title`: Track title
  - `artist`: Artist name
  - `album`: Album name
  - `duration`: Total track duration in seconds
  - `elapsed`: Current playback position in seconds
  - `playback_rate`: Playback speed (1.0 = normal)

### Event Type: `application_changed`

Sent when the active media application switches (e.g., from Spotify to Chrome)

**Fields:**
```json
{
  "event_type": "application_changed",
  "timestamp": 1737496543.456,
  "app_name": "Google Chrome",
  "is_playing": true,
  "playback_state": "playing",
  "playback_state_code": 1
}
```

**Field Details:**
- `app_name`: Name of the new active application
- `is_playing`: Boolean indicating if media is playing (optional)
- `playback_state`: One of "playing", "paused", "not_playing"
- `playback_state_code`: Raw playback state code (optional)

## Example Usage

### Python

```python
import socket
import json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/tmp/media_listener.sock")

buffer = ""
while True:
    data = sock.recv(4096).decode('utf-8')
    buffer += data

    while '\n' in buffer:
        line, buffer = buffer.split('\n', 1)
        event = json.loads(line)

        if event['event_type'] == 'now_playing_info_changed':
            track = event.get('track_info', {})
            print(f"Now playing: {track.get('title')} by {track.get('artist')}")
```

### Shell Script

```bash
#!/bin/bash
while IFS= read -r line; do
    echo "$line" | jq -r '"\(.app_name): \(.track_info.title // "Unknown")"'
done < <(nc -U /tmp/media_listener.sock)
```

### Node.js

```javascript
const net = require('net');

const client = net.createConnection('/tmp/media_listener.sock');
let buffer = '';

client.on('data', (data) => {
    buffer += data.toString();

    let newlineIndex;
    while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
        const line = buffer.substring(0, newlineIndex);
        buffer = buffer.substring(newlineIndex + 1);

        const event = JSON.parse(line);
        console.log('Event:', event);
    }
});
```

## Features

- **Multiple Clients**: Supports multiple simultaneous client connections
- **Non-Blocking**: Server continues monitoring even if no clients are connected
- **Automatic Cleanup**: Disconnected clients are automatically removed
- **Per-App Debouncing**: Events are debounced independently per application
- **Structured Data**: All data is properly typed and structured as JSON

## Notes

- Events are newline-delimited - each JSON object ends with `\n`
- Clients should handle partial reads and buffer data until a complete line is received
- The socket is created fresh each time `media_listener` starts
- Socket is automatically cleaned up on program exit (Ctrl+C)
