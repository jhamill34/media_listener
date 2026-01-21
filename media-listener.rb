class MediaListener < Formula
  desc "Monitor macOS system-wide media playback and publish events over UNIX socket"
  homepage "https://github.com/yourusername/media_listener"
  url "file:///Users/joshuahamill/Code/Personal/media_listener"
  version "1.0.0"

  depends_on :macos

  def install
    # Create headers directory
    (buildpath/"headers").mkpath

    # Copy headers to headers directory
    cp "Sources/media_listener/MediaRemote.h", "headers/"
    cp "Sources/media_listener/BridgingHeader.h", "headers/"

    # Build using Makefile
    system "make", "clean"
    system "make"

    # Install binary
    bin.install "media_listener"

    # Install headers (for reference)
    (prefix/"headers").install Dir["headers/*"]

    # Install example scripts
    (prefix/"examples").mkpath
    (prefix/"examples").install "example_client.py" if File.exist?("example_client.py")
    (prefix/"examples").install "test_socket.sh" if File.exist?("test_socket.sh")
    (prefix/"examples").install "watch_tracks.sh" if File.exist?("watch_tracks.sh")
    (prefix/"examples").install "simple_monitor.sh" if File.exist?("simple_monitor.sh")

    # Install documentation
    (prefix/"docs").mkpath
    (prefix/"docs").install "SOCKET_API.md" if File.exist?("SOCKET_API.md")
  end

  def caveats
    <<~EOS
      media_listener monitors system-wide media playback on macOS.

      Events are published over UNIX socket: /tmp/media_listener.sock

      To start the service:
        brew services start media-listener

      To connect and view events:
        nc -U /tmp/media_listener.sock

      Example scripts are installed at:
        #{prefix}/examples/

      API documentation:
        #{prefix}/docs/SOCKET_API.md
    EOS
  end

  service do
    run [opt_bin/"media_listener"]
    keep_alive true
    log_path var/"log/media_listener.log"
    error_log_path var/"log/media_listener.error.log"
    working_dir var
  end

  test do
    # Test that the binary exists and is executable
    assert_predicate bin/"media_listener", :exist?
    assert_predicate bin/"media_listener", :executable?
  end
end
