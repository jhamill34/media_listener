#!/bin/bash
# Script to install media_listener locally via Homebrew formula

set -e

FORMULA_PATH="$(pwd)/media-listener.rb"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Installing media_listener via Homebrew (local formula)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if formula exists
if [ ! -f "$FORMULA_PATH" ]; then
    echo "Error: Formula not found at $FORMULA_PATH"
    exit 1
fi

# Check if already installed
if brew list media-listener &> /dev/null; then
    echo "media_listener is already installed."
    echo ""
    read -p "Reinstall? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping service if running..."
        brew services stop media-listener 2>/dev/null || true

        echo "Uninstalling..."
        brew uninstall media-listener

        echo "Reinstalling..."
        brew install --build-from-source "$FORMULA_PATH"
    else
        echo "Skipping installation."
        exit 0
    fi
else
    echo "Installing media_listener..."
    brew install --build-from-source "$FORMULA_PATH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo ""
echo "  Start the service:"
echo "    brew services start media-listener"
echo ""
echo "  View status:"
echo "    brew services list | grep media-listener"
echo ""
echo "  Connect to socket:"
echo "    nc -U /tmp/media_listener.sock"
echo ""
echo "  View logs:"
echo "    tail -f \$(brew --prefix)/var/log/media_listener.log"
echo ""
echo "  Example scripts:"
echo "    \$(brew --prefix media-listener)/examples/"
echo ""

# Ask if user wants to start service now
read -p "Start the service now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Starting service..."
    brew services start media-listener

    sleep 2

    echo ""
    echo "Service status:"
    brew services list | grep media-listener

    echo ""
    echo "Socket should be available at: /tmp/media_listener.sock"

    if [ -S /tmp/media_listener.sock ]; then
        echo "✓ Socket is ready!"
    else
        echo "⚠ Socket not found yet (may take a moment to start)"
    fi
fi

echo ""
