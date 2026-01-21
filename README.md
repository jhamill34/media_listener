# Media Listener

A macOS system-wide media playback monitor that publishes real-time events over a UNIX socket.

## Features

- 🎵 **System-Wide Monitoring** - Tracks media from Spotify, Chrome, Safari, Music.app, etc.
- 📡 **UNIX Socket API** - Publishes JSON events for easy integration
- 🔄 **Per-App Debouncing** - Independent tracking for each application
- 🚀 **Homebrew Service** - Install and run as a background service
- 🎯 **Track Change Detection** - Filters out duplicate events
- 📊 **Structured Events** - Clean JSON format with full metadata
- ⚡ **Instant State** - New clients receive current playback state immediately
- 🔄 **Periodic Updates** - Heartbeat every 15 seconds with last known state
- 🛡️ **Robust** - Exception handling and thread-safe operations

## Quick Start

### Option 1: Homebrew Tap (Recommended)

```bash
# Add the tap
brew tap yourusername/media

# Install media listener
brew install media-listener

# Start the service
brew services start media-listener

# Optional: Install SketchyBar integration
brew install sketchybar-media-listener
brew services start sketchybar-media-listener
```

### Option 2: Local Development Install

```bash
# Install from local formula
brew install --build-from-source --HEAD Formula/media-listener.rb

# Start service
brew services start media-listener
```

### Option 3: Manual Build

```bash
# Build
make

# Run
./media_listener
```

## Installation

### Homebrew Tap

The recommended way to install is via Homebrew tap:

```bash
brew tap yourusername/media
brew install media-listener

# Optional: SketchyBar integration
brew install sketchybar-media-listener
```

See [TAP_SETUP.md](TAP_SETUP.md) for creating your own tap.

### Local Development

For development or contributing:

```bash
# Clone repository
git clone <repo-url>
cd media_listener

# Build
make

# Run
./media_listener
```

## Usage

### Starting the Listener

**As a service:**
```bash
brew services start media-listener
```

**Manually:**
```bash
./media_listener
```

### Connecting to Events

**Using netcat:**
```bash
nc -U /tmp/media_listener.sock
```

**Using Python client:**
```bash
./example_client.py
```

**Using bash scripts:**
```bash
# Full event details
./test_socket.sh

# Track changes only
./watch_tracks.sh

# Simple one-line format
./simple_monitor.sh
```

## Socket API

Events are published as newline-delimited JSON over `/tmp/media_listener.sock`.

### Event Types

#### `current_state`

Sent immediately when a client connects and periodically every 5 seconds.

```json
{
  "event_type": "current_state",
  "timestamp": 1737496543.789,
  "app_name": "Spotify",
  "playback_state": "playing",
  "track_info": {
    "title": "Song Title",
    "artist": "Artist Name",
    "elapsed": 35.2
  }
}
```

#### `now_playing_info_changed`

```json
{
  "event_type": "now_playing_info_changed",
  "timestamp": 1737496543.123,
  "event_number": 42,
  "track_changed": true,
  "app_name": "Spotify",
  "app_pid": 12345,
  "playback_state": "playing",
  "track_info": {
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Name",
    "duration": 240.5,
    "elapsed": 30.2
  }
}
```

#### `application_changed`

```json
{
  "event_type": "application_changed",
  "timestamp": 1737496543.456,
  "app_name": "Google Chrome",
  "playback_state": "playing"
}
```

See [SOCKET_API.md](SOCKET_API.md) for complete API documentation.

## Integration Examples

### Python

```python
import socket
import json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/tmp/media_listener.sock")

for line in sock.makefile():
    event = json.loads(line)
    if event['event_type'] == 'now_playing_info_changed':
        track = event.get('track_info', {})
        print(f"{track.get('title')} - {track.get('artist')}")
```

### Shell Script

```bash
nc -U /tmp/media_listener.sock | while read line; do
    echo "$line" | jq -r '.track_info.title'
done
```

### SketchyBar Integration

```bash
# In simple_monitor.sh (already configured)
sketchybar --trigger custom_media_change MEDIA_INFO="$line"
```

## Service Management

```bash
# Start
brew services start media-listener

# Stop
brew services stop media-listener

# Restart
brew services restart media-listener

# Status
brew services list | grep media-listener

# Logs
tail -f $(brew --prefix)/var/log/media_listener.log
```

## Configuration

### Debounce Interval

Edit `main.m` line 9:

```objc
static const NSTimeInterval DEBOUNCE_INTERVAL = 0.5; // 500ms
```

### State Update Interval

Edit `main.m` line 10:

```objc
static const NSTimeInterval STATE_UPDATE_INTERVAL = 15.0; // 15 seconds
```

### Socket Path

Edit `main.m` line 11:

```objc
static NSString * const SOCKET_PATH = @"/tmp/media_listener.sock";
```

## Building

### Requirements

- macOS (uses private MediaRemote framework)
- Xcode Command Line Tools
- clang with Objective-C support

### Build Commands

```bash
# Build
make

# Clean
make clean

# Build and run
make run
```

## Development

### Project Structure

```
media_listener/
├── main.m                    # Main Objective-C source
├── headers/
│   ├── MediaRemote.h        # MediaRemote framework interface
│   └── BridgingHeader.h     # Header bridge
├── Makefile                 # Build configuration
├── media-listener.rb        # Homebrew formula
├── example_client.py        # Python client example
├── test_socket.sh          # Full event viewer
├── watch_tracks.sh         # Track changes only
├── simple_monitor.sh       # One-line format
└── SOCKET_API.md           # API documentation
```

### Testing

```bash
# Test socket communication
./test_disconnect.sh

# Monitor events
./test_socket.sh

# Watch track changes
./watch_tracks.sh
```

## Architecture

- **MediaRemote Framework**: macOS private framework for media monitoring
- **Dispatch Queues**: Thread-safe event handling
- **UNIX Sockets**: Non-blocking socket server with multiple client support
- **Per-App State**: Independent debouncing and tracking for each application
- **Graceful Degradation**: Handles client disconnects without crashing

## Troubleshooting

### Service won't start

```bash
# Check logs
tail -f $(brew --prefix)/var/log/media_listener.error.log

# Try running manually
$(brew --prefix)/bin/media_listener
```

### No events received

1. Check if the service is running: `brew services list`
2. Verify socket exists: `ls -l /tmp/media_listener.sock`
3. Try playing media in Spotify or Chrome
4. Check debug output in logs

### Socket connection refused

```bash
# Restart the service
brew services restart media-listener

# Check if socket file exists
ls -l /tmp/media_listener.sock
```

## License

MIT

## Credits

Uses Apple's private MediaRemote framework for system-wide media monitoring.
