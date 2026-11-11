# MediaStreamer 0.3 playback upgrade

This version keeps the native yt-dlp/FFmpeg downloader and the small Android
share dialog over YouTube. Home is still the download dashboard. Video, Audio,
Browse, Playlists and More add library navigation; saved links and the original
download library are reachable from More. Notes, browser, webhook settings and
LAN sender/receiver remain available. Existing SQLite tables are unchanged.

## Implemented

| Area | Behavior |
| --- | --- |
| Engine | LibVLC Android 3.7.5; one foreground-service-owned decoder |
| Navigation | Persistent mini player on tab pages and pushed routes; leaving the player keeps listening |
| Video | Fullscreen, rotation, fit/fill/aspect ratios, screen lock, configurable auto-hide |
| Touch | Double-tap skip, horizontal seek, vertical brightness/volume, temporary hold speed |
| Speed | 0.25–8×, presets, global or per-media memory; pitch-preserving time stretch |
| Audio | Background playback, lockscreen/media notifications, headset/Bluetooth controls, audio focus/ducking and unplug pause |
| Timing | Sleep timer, finish-track-after-deadline, strict jump-to-time input, A–B repeat |
| Sound | LibVLC 10-band equalizer, preamp, presets and persisted custom settings |
| Tracks | Audio/video/subtitle selection, external subtitle picker, audio/subtitle delays, chapters |
| Queue | Previous/next, repeat off/one/all, shuffle, reorder/remove/add, play next, save playlists |
| Library | Video folder collages and grid/list, search, audio artists/albums/tracks/genres, favorites, watched markers, multiple selection |
| Sorting | Title, filename, duration, insertion date, size, either direction |
| Files | Metadata, share, rename and deletion; Android consent for media owned by other apps |
| Bookmarks | Named timestamp bookmarks saved per URI; seek/delete |
| Playlists | Existing SQLite playlists, ordered queue playback, import M3U/PLS, export M3U |
| Network | Saved media/stream URLs: HTTP(S), RTSP/RTMP/RTP/UDP, SMB/FTP/SFTP/NFS via LibVLC |
| Casting | LibVLC compatible-renderer discovery and selection; existing LAN HTTP streaming remains separate |
| Notes | Single-video post-watch prompt; save/keep/delete; notes menu remains available for queued media |

## Actual limits

This is a substantial VLC-style feature set, not a complete port of VLC Android.
Android Auto/Android TV interfaces, UPnP/SMB folder discovery and credential UI,
DVD/Blu-ray navigation, subtitle online search, ReplayGain configuration,
audio visualizations, video filters/cropping, frame-by-frame controls, audio
passthrough routing and every VLC advanced setting are not implemented.
Network locations open media/stream URLs; they are not a remote directory
browser. MediaStore genre availability depends on Android/provider metadata.
Relative paths inside document-provider playlists cannot be resolved across
arbitrary provider siblings: use absolute paths or stream URLs. Imported saved
URIs need their original persisted read permission on the same device.
Playback rates, codecs, casting, embedded subtitles, HDR, hardware acceleration
and audio output depend on the media and Android device. Disabling hardware
decoding and retrying is available for codec-specific failures.

## Architecture and resource bounds

The service owns playback, queue, resume points and sleep/loop timers. Changing
Flutter routes only attaches/detaches the video surface. A codec is not created
when merely browsing/restoring the saved queue. Paused playback reduces native
polling; Flutter stops polling when backgrounded outside picture-in-picture.
MediaStore queries and document IO use workers; thumbnails are lazy with a
96-entry future cache and at most two native jobs. Android audio focus and a
bounded partial wake lock keep background playback coherent. Releasing the
native player occurs away from the UI thread.

## Validation

Run `flutter analyze` and `flutter test`. Native queue policy, cold service state
and downloader regression tests run with `:app:testReleaseUnitTest`.
Flutter UI tests check Arabic title/search rendering, the 220-track list,
display controls, nested-page mini player visibility and playback menus.
These checks do not execute real LibVLC decoding or the external YouTube app.

Device acceptance is required before calling this production-ready:

1. Install the ARM64 test APK. Back up notes/links before removing any older
   build if Android reports a signing-key conflict. Release evaluation builds
   use a test/debug certificate, not the owner's production key.
2. Share public YouTube videos/Shorts to MediaStreamer with the app stopped and
   running. Choose MP4/M4A/MP3, continue using YouTube and inspect notifications.
   Repeat with accessible Facebook reels/watch/share URLs and other supported
   social sites. Login-only/DRM content should fail visibly.
3. Open local video, audio and document-provider media. Navigate through all
   tabs and pushed pages; return through the mini player. Check no duplicate
   audio/decoder and no loss of queue or position.
4. Test lockscreen/Bluetooth/headset controls, interruptions by a phone call,
   ducking, unplug pause, background playback and process restart.
5. Test speed scope, equalizer, sleep/finish-track, A–B, bookmarks, chapters,
   external and embedded subtitles, negative/positive sync and software decoder.
6. Test PiP, rotation, multi-window, fast back/forward navigation and leaving the
   route while a file is opening. Check screen brightness restores on exit.
7. Try queue end/repeat/shuffle, reorder the current item, remove it and play an
   imported playlist. Delete/rename own files and files requiring Android consent.
8. Open network media; disconnect/reconnect Wi-Fi. Discover/cast on a compatible
   receiver and stop casting. Confirm useful errors for unavailable resources.
9. Verify notes save/keep/delete, existing playlists/links, downloaded files,
   browser detection, webhook options and LAN streaming still work.

The new engine and live social extractors have not been tested on a physical
Android device in this build environment. Report device/Android version, exact
steps and a sample accessible URL for any failure.
