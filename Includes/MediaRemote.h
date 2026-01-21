#ifndef MediaRemote_h
#define MediaRemote_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Notification names
extern NSString * const kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern NSString * const kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification;
extern NSString * const kMRMediaRemoteNowPlayingApplicationDidChangeNotification;

// Dictionary keys for now playing info
extern NSString * const kMRMediaRemoteNowPlayingInfoArtist;
extern NSString * const kMRMediaRemoteNowPlayingInfoAlbum;
extern NSString * const kMRMediaRemoteNowPlayingInfoTitle;
extern NSString * const kMRMediaRemoteNowPlayingInfoDuration;
extern NSString * const kMRMediaRemoteNowPlayingInfoElapsedTime;
extern NSString * const kMRMediaRemoteNowPlayingInfoPlaybackRate;
extern NSString * const kMRMediaRemoteNowPlayingInfoArtworkData;

// Functions
void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
void MRMediaRemoteUnregisterForNowPlayingNotifications(void);
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^block)(CFDictionaryRef));
void MRMediaRemoteGetNowPlayingApplicationDisplayName(dispatch_queue_t queue, void (^block)(NSString *));
void MRMediaRemoteGetNowPlayingClient(dispatch_queue_t queue, void (^block)(id));

#ifdef __cplusplus
}
#endif

#endif /* MediaRemote_h */
