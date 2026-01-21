#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <errno.h>
#import "headers/MediaRemote.h"

// Configuration
static const NSTimeInterval DEBOUNCE_INTERVAL = 0.5; // 500ms debounce
static const NSTimeInterval STATE_UPDATE_INTERVAL = 15.0; // 5 seconds - periodic state updates
static NSString * const SOCKET_PATH = @"/tmp/media_listener.sock";

// Per-app state tracking
@interface AppState : NSObject
@property (nonatomic) NSTimeInterval lastEventTime;
@property (nonatomic, copy) NSString *lastTitle;
@property (nonatomic, copy) NSString *lastArtist;
@property (nonatomic, copy) NSString *lastAlbum;
@end

@implementation AppState
@end

// Global state
static int changeCount = 0;
static dispatch_queue_t callbackQueue;
static NSMutableDictionary<NSString *, AppState *> *appStates;

// Socket state
static int serverSocket = -1;
static NSMutableArray<NSNumber *> *clientSockets;
static dispatch_queue_t socketQueue;
static dispatch_source_t acceptSource;
static dispatch_source_t periodicTimer;

// Current state cache
static NSMutableDictionary *currentStateCache;

// Socket helper functions
void sendJSONToClient(int clientFd, NSDictionary *data) {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data
                                                       options:0
                                                         error:&error];
    if (!jsonData) {
        printf("[ERROR] Error serializing JSON: %s\n", [[error localizedDescription] UTF8String]);
        return;
    }

    NSMutableData *messageData = [jsonData mutableCopy];
    [messageData appendBytes:"\n" length:1];

    ssize_t sent = write(clientFd, [messageData bytes], [messageData length]);
    if (sent < 0) {
        printf("[WARN] Failed to send to client %d: %s\n", clientFd, strerror(errno));
    }
}

void broadcastJSON(NSDictionary *data) {
    printf("[DEBUG] broadcastJSON called\n");

    // Update state cache
    if (data[@"event_type"]) {
        currentStateCache = [data mutableCopy];
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data
                                                       options:0
                                                         error:&error];
    if (!jsonData) {
        printf("[ERROR] Error serializing JSON: %s\n", [[error localizedDescription] UTF8String]);
        return;
    }

    printf("[DEBUG] JSON serialized, size: %lu bytes\n", (unsigned long)[jsonData length]);

    NSMutableData *messageData = [jsonData mutableCopy];
    [messageData appendBytes:"\n" length:1]; // Add newline delimiter

    dispatch_async(socketQueue, ^{
        printf("[DEBUG] Broadcasting to %lu clients\n", (unsigned long)[clientSockets count]);

        if ([clientSockets count] == 0) {
            printf("[DEBUG] No clients connected\n");
            return;
        }

        NSMutableIndexSet *disconnectedClients = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < [clientSockets count]; i++) {
            int clientFd = [clientSockets[i] intValue];

            // Try to write to client, handling all error cases gracefully
            ssize_t sent = write(clientFd, [messageData bytes], [messageData length]);

            if (sent < 0) {
                // Client is gone or error occurred
                if (errno == EPIPE || errno == ECONNRESET || errno == ENOTCONN) {
                    printf("[INFO] Client %d disconnected (error: %s)\n", clientFd, strerror(errno));
                } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    // Non-blocking would block, try again later (or just skip)
                    printf("[WARN] Client %d socket would block, skipping\n", clientFd);
                    continue;
                } else {
                    printf("[WARN] Write error to client %d: %s\n", clientFd, strerror(errno));
                }
                [disconnectedClients addIndex:i];
                close(clientFd);
            } else if (sent < [messageData length]) {
                // Partial write - for simplicity, we'll disconnect the client
                printf("[WARN] Partial write to client %d (%zd/%lu bytes), disconnecting\n",
                       clientFd, sent, (unsigned long)[messageData length]);
                [disconnectedClients addIndex:i];
                close(clientFd);
            } else {
                printf("[DEBUG] Sent %zd bytes to client %d\n", sent, clientFd);
            }
        }

        // Remove disconnected clients
        if ([disconnectedClients count] > 0) {
            [clientSockets removeObjectsAtIndexes:disconnectedClients];
            printf("[INFO] Removed %lu disconnected client(s), %lu remaining\n",
                   (unsigned long)[disconnectedClients count],
                   (unsigned long)[clientSockets count]);
        }
    });
}

void sendCurrentStateToClient(int clientFd) {
    dispatch_async(socketQueue, ^{
        if (!currentStateCache || [currentStateCache count] == 0) {
            printf("[DEBUG] No cached state available to send to client %d\n", clientFd);
            return;
        }

        NSMutableDictionary *stateEvent = [currentStateCache mutableCopy];
        stateEvent[@"event_type"] = @"current_state";
        stateEvent[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);

        sendJSONToClient(clientFd, stateEvent);
        printf("[INFO] Sent current state to client %d\n", clientFd);
    });
}

void setupSocketServer(void) {
    socketQueue = dispatch_queue_create("com.mediaListener.socket", DISPATCH_QUEUE_SERIAL);
    clientSockets = [NSMutableArray array];

    // Remove existing socket file
    unlink([SOCKET_PATH UTF8String]);

    // Create socket
    serverSocket = socket(AF_UNIX, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        perror("socket");
        return;
    }

    // Make socket non-blocking
    int flags = fcntl(serverSocket, F_GETFL, 0);
    fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK);

    // Bind socket
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [SOCKET_PATH UTF8String], sizeof(addr.sun_path) - 1);

    if (bind(serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(serverSocket);
        return;
    }

    // Listen
    if (listen(serverSocket, 5) < 0) {
        perror("listen");
        close(serverSocket);
        return;
    }

    printf("Socket server listening on %s\n", [SOCKET_PATH UTF8String]);

    // Accept connections on background queue
    acceptSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_READ, serverSocket, 0, socketQueue);

    if (!acceptSource) {
        printf("[ERROR] Failed to create dispatch source\n");
        return;
    }

    dispatch_source_set_event_handler(acceptSource, ^{
        printf("[DEBUG] Accept handler triggered\n");
        while (1) {
            int clientFd = accept(serverSocket, NULL, NULL);
            if (clientFd < 0) {
                if (errno != EAGAIN && errno != EWOULDBLOCK) {
                    perror("[DEBUG] accept");
                }
                break;
            }

            printf("[DEBUG] Accepted client connection: fd=%d\n", clientFd);

            // Make client socket non-blocking
            int flags = fcntl(clientFd, F_GETFL, 0);
            fcntl(clientFd, F_SETFL, flags | O_NONBLOCK);

            // Prevent SIGPIPE on write to disconnected client (macOS/BSD specific)
            int set = 1;
            if (setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &set, sizeof(set)) < 0) {
                printf("[WARN] Failed to set SO_NOSIGPIPE on client %d: %s\n", clientFd, strerror(errno));
            }

            [clientSockets addObject:@(clientFd)];
            printf("[INFO] Client %d connected (total: %lu)\n", clientFd, (unsigned long)[clientSockets count]);

            // Send current state to newly connected client
            sendCurrentStateToClient(clientFd);
        }
    });

    dispatch_resume(acceptSource);
    printf("[DEBUG] Dispatch source resumed\n");

    // Setup periodic state updates
    periodicTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (periodicTimer) {
        dispatch_source_set_timer(periodicTimer,
                                 dispatch_time(DISPATCH_TIME_NOW, STATE_UPDATE_INTERVAL * NSEC_PER_SEC),
                                 STATE_UPDATE_INTERVAL * NSEC_PER_SEC,
                                 0.5 * NSEC_PER_SEC);

        dispatch_source_set_event_handler(periodicTimer, ^{
            dispatch_async(socketQueue, ^{
                if ([clientSockets count] == 0) {
                    return;
                }

                printf("[DEBUG] Periodic state update triggered\n");

                // Broadcast current state to all connected clients
                for (NSNumber *clientNum in [clientSockets copy]) {
                    int clientFd = [clientNum intValue];
                    sendCurrentStateToClient(clientFd);
                }
            });
        });

        dispatch_resume(periodicTimer);
        printf("[DEBUG] Periodic timer started (interval: %.0fs)\n", STATE_UPDATE_INTERVAL);
    }
}

void cleanupSocketServer(void) {
    if (periodicTimer) {
        dispatch_source_cancel(periodicTimer);
        periodicTimer = NULL;
    }

    if (acceptSource) {
        dispatch_source_cancel(acceptSource);
        acceptSource = NULL;
    }

    if (serverSocket >= 0) {
        close(serverSocket);
        unlink([SOCKET_PATH UTF8String]);
    }

    for (NSNumber *clientNum in clientSockets) {
        close([clientNum intValue]);
    }
}

void signalHandler(int sig) {
    if (sig == SIGINT) {
        printf("\nShutting down...\n");
        cleanupSocketServer();
        exit(0);
    }
    // Ignore SIGPIPE - we handle broken pipes via write() return codes
}

void handleNowPlayingInfoDidChange(NSNotification *notification) {
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        return;
    }

    // Extract app name to determine which app's state to use
    NSString *appName = userInfo[@"kMRMediaRemoteNowPlayingApplicationDisplayNameUserInfoKey"];
    if (!appName) {
        appName = @"Unknown";
    }

    // Get or create state for this app
    AppState *appState = appStates[appName];
    if (!appState) {
        appState = [[AppState alloc] init];
        appState.lastEventTime = 0;
        appStates[appName] = appState;
    }

    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval timeSinceLastEvent = currentTime - appState.lastEventTime;

    // Get the track info to determine if this is a real change
    MRMediaRemoteGetNowPlayingInfo(callbackQueue, ^(CFDictionaryRef infoRef) {
        if (!infoRef) {
            return;
        }

        CFRetain(infoRef);
        NSDictionary *nsDict = (__bridge NSDictionary *)infoRef;

        if (!nsDict) {
            CFRelease(infoRef);
            return;
        }

        NSString *currentTitle = nsDict[kMRMediaRemoteNowPlayingInfoTitle];
        NSString *currentArtist = nsDict[kMRMediaRemoteNowPlayingInfoArtist];
        NSString *currentAlbum = nsDict[kMRMediaRemoteNowPlayingInfoAlbum];

        // Check if track has actually changed for this specific app
        BOOL trackChanged = NO;
        if (currentTitle && ![currentTitle isEqualToString:appState.lastTitle]) {
            trackChanged = YES;
        } else if (currentArtist && ![currentArtist isEqualToString:appState.lastArtist]) {
            trackChanged = YES;
        } else if (currentAlbum && ![currentAlbum isEqualToString:appState.lastAlbum]) {
            trackChanged = YES;
        } else if (!currentTitle && !currentArtist && !currentAlbum &&
                   (appState.lastTitle || appState.lastArtist || appState.lastAlbum)) {
            trackChanged = YES;
        }

        // Apply debouncing: only process if track changed OR enough time has passed
        if (!trackChanged && timeSinceLastEvent < DEBOUNCE_INTERVAL) {
            CFRelease(infoRef);
            return;
        }

        // Update this app's state
        appState.lastEventTime = currentTime;
        appState.lastTitle = [currentTitle copy];
        appState.lastArtist = [currentArtist copy];
        appState.lastAlbum = [currentAlbum copy];

        // Now display the event
        changeCount++;
        printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
        printf("[%d] Media Event", changeCount);
        if (trackChanged) {
            printf(" 📀 Track Changed");
        }
        printf("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

        // Display app name
        printf("App: %s\n", [appName UTF8String]);

        // Extract playback state
        NSNumber *playbackStateNum = userInfo[@"kMRMediaRemotePlaybackStateUserInfoKey"];
        if (playbackStateNum) {
            int playbackState = [playbackStateNum intValue];
            const char *state = playbackState == 1 ? "Playing" : playbackState == 2 ? "Paused" : "Stopped";
            printf("State: %s\n", state);
        } else {
            NSNumber *isPlayingNum = userInfo[@"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"];
            if (isPlayingNum) {
                BOOL isPlaying = [isPlayingNum boolValue];
                printf("State: %s\n", isPlaying ? "Playing" : "Paused");
            }
        }

        // Extract process ID
        NSNumber *pidNum = userInfo[@"kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey"];
        if (pidNum) {
            printf("PID: %d\n", [pidNum intValue]);
        }

        // Display track info
        NSMutableDictionary *result = [NSMutableDictionary dictionary];

        if (currentTitle) {
            result[kMRMediaRemoteNowPlayingInfoTitle] = currentTitle;
        }
        if (currentArtist) {
            result[kMRMediaRemoteNowPlayingInfoArtist] = currentArtist;
        }
        if (currentAlbum) {
            result[kMRMediaRemoteNowPlayingInfoAlbum] = currentAlbum;
        }

        id duration = nsDict[kMRMediaRemoteNowPlayingInfoDuration];
        if (duration) {
            result[kMRMediaRemoteNowPlayingInfoDuration] = duration;
        }

        id elapsed = nsDict[kMRMediaRemoteNowPlayingInfoElapsedTime];
        if (elapsed) {
            result[kMRMediaRemoteNowPlayingInfoElapsedTime] = elapsed;
        }

        id rate = nsDict[kMRMediaRemoteNowPlayingInfoPlaybackRate];
        if (rate) {
            result[kMRMediaRemoteNowPlayingInfoPlaybackRate] = rate;
        }

        if ([result count] > 0) {
            printf("%s\n", [[result description] UTF8String]);
        }

        printf("\n");

        // Broadcast structured data over socket
        NSMutableDictionary *jsonEvent = [NSMutableDictionary dictionary];
        jsonEvent[@"event_type"] = @"now_playing_info_changed";
        jsonEvent[@"timestamp"] = @(currentTime);
        jsonEvent[@"event_number"] = @(changeCount);
        jsonEvent[@"track_changed"] = @(trackChanged);

        // App info
        jsonEvent[@"app_name"] = appName;
        if (pidNum) {
            jsonEvent[@"app_pid"] = pidNum;
        }

        // Playback state
        if (playbackStateNum) {
            int playbackState = [playbackStateNum intValue];
            NSString *stateStr = playbackState == 1 ? @"playing" : playbackState == 2 ? @"paused" : @"stopped";
            jsonEvent[@"playback_state"] = stateStr;
            jsonEvent[@"playback_state_code"] = playbackStateNum;
        } else {
            NSNumber *isPlayingNum = userInfo[@"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"];
            if (isPlayingNum) {
                jsonEvent[@"playback_state"] = [isPlayingNum boolValue] ? @"playing" : @"paused";
            }
        }

        // Track info
        NSMutableDictionary *trackInfo = [NSMutableDictionary dictionary];
        if (currentTitle) trackInfo[@"title"] = currentTitle;
        if (currentArtist) trackInfo[@"artist"] = currentArtist;
        if (currentAlbum) trackInfo[@"album"] = currentAlbum;
        if (duration) trackInfo[@"duration"] = duration;
        if (elapsed) trackInfo[@"elapsed"] = elapsed;
        if (rate) trackInfo[@"playback_rate"] = rate;

        if ([trackInfo count] > 0) {
            jsonEvent[@"track_info"] = trackInfo;
        }

        broadcastJSON(jsonEvent);

        CFRelease(infoRef);
    });
}

void handleNowPlayingApplicationDidChange(NSNotification *notification) {
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("🔄 Application Switched\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    NSDictionary *userInfo = notification.userInfo;
    if (userInfo) {
        NSString *appName = userInfo[@"kMRMediaRemoteNowPlayingApplicationDisplayNameUserInfoKey"];
        if (appName) {
            printf("New App: %s\n", [appName UTF8String]);

            NSNumber *isPlayingNum = userInfo[@"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"];
            if (isPlayingNum) {
                BOOL isPlaying = [isPlayingNum boolValue];
                printf("State: %s\n", isPlaying ? "Playing" : "Not Playing");
            }

            NSNumber *playbackStateNum = userInfo[@"kMRMediaRemotePlaybackStateUserInfoKey"];
            if (playbackStateNum) {
                int playbackState = [playbackStateNum intValue];
                const char *state = playbackState == 1 ? "Playing" : playbackState == 2 ? "Paused" : "Stopped";
                printf("Playback: %s\n", state);
            }

            // Broadcast application change event
            NSMutableDictionary *jsonEvent = [NSMutableDictionary dictionary];
            jsonEvent[@"event_type"] = @"application_changed";
            jsonEvent[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            jsonEvent[@"app_name"] = appName;

            if (isPlayingNum) {
                jsonEvent[@"is_playing"] = isPlayingNum;
                jsonEvent[@"playback_state"] = [isPlayingNum boolValue] ? @"playing" : @"not_playing";
            }

            if (playbackStateNum) {
                int playbackState = [playbackStateNum intValue];
                NSString *stateStr = playbackState == 1 ? @"playing" : playbackState == 2 ? @"paused" : @"stopped";
                jsonEvent[@"playback_state"] = stateStr;
                jsonEvent[@"playback_state_code"] = playbackStateNum;
            }

            broadcastJSON(jsonEvent);
        }
    }
    printf("\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Initialize per-app state tracking
        appStates = [NSMutableDictionary dictionary];
        currentStateCache = [NSMutableDictionary dictionary];

        callbackQueue = dispatch_queue_create("com.mediaListener.callbacks",
                                             dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                                     QOS_CLASS_USER_INITIATED,
                                                                                     0));

        // Setup socket server
        setupSocketServer();

        // Setup signal handlers
        signal(SIGINT, signalHandler);  // Handle Ctrl+C for cleanup
        signal(SIGPIPE, SIG_IGN);       // Ignore SIGPIPE (handle via write errors)

        printf("Starting MediaRemote listener...\n");
        printf("Monitoring system-wide media playback\n\n");

        MRMediaRemoteRegisterForNowPlayingNotifications(callbackQueue);

        [[NSNotificationCenter defaultCenter] addObserverForName:
            [NSNotification notificationWithName:kMRMediaRemoteNowPlayingInfoDidChangeNotification
                                          object:nil].name
                                                           object:nil
                                                            queue:[NSOperationQueue mainQueue]
                                                       usingBlock:^(NSNotification *note) {
            handleNowPlayingInfoDidChange(note);
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:
            [NSNotification notificationWithName:kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                          object:nil].name
                                                           object:nil
                                                            queue:[NSOperationQueue mainQueue]
                                                       usingBlock:^(NSNotification *note) {
            handleNowPlayingApplicationDidChange(note);
        }];

        printf("Listener active. Press Ctrl+C to stop.\n");
        printf("\nFeatures:\n");
        printf("  • Tracks which app is playing (Spotify, Chrome, etc.)\n");
        printf("  • Shows playback state (Playing/Paused)\n");
        printf("  • Detects when tracks change\n");
        printf("  • Per-app debouncing (%.0fms threshold)\n", DEBOUNCE_INTERVAL * 1000);
        printf("  • Independent tracking for each application\n");
        printf("  • Filters out rapid track skipping\n");
        printf("  • Publishes JSON events over UNIX socket\n");
        printf("  • Sends current state on client connect\n");
        printf("  • Periodic state updates (%.0fs interval)\n", STATE_UPDATE_INTERVAL);
        printf("\nSocket API:\n");
        printf("  • Path: %s\n", [SOCKET_PATH UTF8String]);
        printf("  • Format: JSON (newline-delimited)\n");
        printf("  • Connect with: nc -U %s\n", [SOCKET_PATH UTF8String]);
        printf("\n");

        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
