# Homebrew Installation

## Quick Start (Local Install)

Install directly from the local formula:

```bash
# Install the formula
brew install --build-from-source ./media-listener.rb

# Start as a service
brew services start media-listener

# Check service status
brew services info media-listener

# View logs
tail -f /opt/homebrew/var/log/media_listener.log
```

## Creating a Homebrew Tap (For Distribution)

If you want to distribute this via a Homebrew tap:

### 1. Create a GitHub repository for your tap

```bash
# Create a repo named: homebrew-tap
# GitHub URL would be: github.com/yourusername/homebrew-tap
```

### 2. Copy the formula to your tap

```bash
git clone https://github.com/yourusername/homebrew-tap
cd homebrew-tap
cp /path/to/media-listener.rb Formula/media-listener.rb
git add Formula/media-listener.rb
git commit -m "Add media-listener formula"
git push
```

### 3. Users can then install via tap

```bash
# Add your tap
brew tap yourusername/tap

# Install media-listener
brew install media-listener

# Start the service
brew services start media-listener
```

## Service Management

### Start the service

```bash
brew services start media-listener
```

### Stop the service

```bash
brew services stop media-listener
```

### Restart the service

```bash
brew services restart media-listener
```

### View service status

```bash
brew services list | grep media-listener
```

### View logs

```bash
# Standard output
tail -f /opt/homebrew/var/log/media_listener.log

# Error output
tail -f /opt/homebrew/var/log/media_listener.error.log
```

## Connecting to the Socket

Once the service is running:

```bash
# Using netcat
nc -U /tmp/media_listener.sock

# Using the example Python client
$(brew --prefix media-listener)/examples/example_client.py

# Using the simple monitor
$(brew --prefix media-listener)/examples/simple_monitor.sh
```

## Uninstalling

```bash
# Stop the service first
brew services stop media-listener

# Uninstall
brew uninstall media-listener
```

## Development

If you're actively developing, you can use the local formula:

```bash
# Reinstall after making changes
brew reinstall --build-from-source ./media-listener.rb

# Or unlink/link to test new builds
brew unlink media-listener
make clean && make
brew link media-listener
```

## Updating the Formula for Distribution

Before publishing to a tap, you need to update the formula with proper URLs:

1. **Create a release** on GitHub with a tarball
2. **Update the `url`** in the formula to point to the release tarball
3. **Calculate SHA256** of the tarball:
   ```bash
   shasum -a 256 media_listener-1.0.0.tar.gz
   ```
4. **Add the SHA256** to the formula:
   ```ruby
   url "https://github.com/yourusername/media_listener/archive/v1.0.0.tar.gz"
   sha256 "abc123..."
   ```

## Formula Structure

The formula includes:

- **Binary**: `media_listener` installed to `bin/`
- **Headers**: Reference headers in `#{prefix}/headers/`
- **Examples**: Scripts in `#{prefix}/examples/`
- **Docs**: API documentation in `#{prefix}/docs/`
- **Service**: Configured to run as a background service
- **Logs**: Automatically logged to `/opt/homebrew/var/log/`

## Notes

- The service runs with `keep_alive true`, so it will restart if it crashes
- Logs are rotated automatically by launchd
- The socket is created at `/tmp/media_listener.sock`
- The service requires macOS (uses private MediaRemote framework)
