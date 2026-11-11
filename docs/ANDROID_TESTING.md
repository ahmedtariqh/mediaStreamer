# Android download verification

## Build

Requires Flutter 3.47.9 (Dart 3.13), Java 17 or 21 and Android SDK 36.
Android 7.0/API 24 is the minimum due to the embedded downloader.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
cd android
./gradlew :app:testReleaseUnitTest -Ptarget-platform=android-arm64 -Psplit-per-abi=true --max-workers=1
```

The ARM64 APK is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

The APK uses the repository's existing debug signing configuration. A previously
installed build signed with a different key cannot be upgraded with this APK.
Back up notes/links/settings before removing an older app; public Downloads are
separate from app data. Production signing requires the owner's original key.

## On-device acceptance checks

These require the actual Android YouTube/social apps, real accessible videos,
and an Android device. Unit tests do not establish live platform compatibility.

1. With MediaStreamer stopped, open a public YouTube video. Share → MediaStreamer.
   Choose a video quality. The dialog must close back to YouTube, and the
   download notification must progress while watching another video.
2. Repeat with the main app already running, then share a second video while
   the first downloads. They must appear in the same queue and history.
3. Share YouTube Shorts, mobile watch URLs, and text containing a title + URL.
4. Download the same video as M4A and MP3. Play both in MediaStreamer and an
   external player. Test Bluetooth output and background/lockscreen controls.
5. Download an adaptive 1080p stream and confirm the final file contains both
   video and sound. Test a silent video and an audio-only source separately.
6. Try public Facebook watch/reel/share/fb.watch, Instagram reel, TikTok,
   X/Twitter video and Vimeo links. Private, login-required, DRM-protected,
   geo-restricted and unsupported posts must show a useful error, not crash.
7. Pause/resume repeatedly during network transfer and immediately after
   selecting a format. Cancel both queued and running tasks. Check for no
   completed-looking partial files in public Downloads.
8. Lose network connectivity, run out of storage, deny notification permission,
   and deny legacy storage permission (API 24–28). Failures must be visible and
   retryable. Notification denial on Android 13+ must not block downloads.
9. Force-stop/restart the app during transfer. Interrupted tasks should be
   paused; resume should reuse the staged file when the source supports ranges.
   Android force-stop intentionally terminates all services until next launch.
10. On API 35+, shorten the data-sync timeout with Android developer tooling.
    Verify the timeout pauses tasks and stops the foreground service cleanly.
11. Leave the player immediately during initialization, retry playback, and
    open several large local files. No disposed-controller errors or UI stalls.
12. Verify completed files in Downloads/MediaStreamer, delete a file externally,
    and confirm the app reports it missing on refresh/reopening.

## Implementation

The native ShareActivity uses a standard translucent activity/dialog, without
SYSTEM_ALERT_WINDOW. It never opens the full Flutter app and finishes after the
foreground service accepts a task. Android's share sheet still appears because
that is the official YouTube app's sharing mechanism.

One foreground worker bounds simultaneous FFmpeg/decoder memory usage.
Downloads/partial fragments live in the app's external files directory until
completion; Android 10+ publishes through MediaStore with IS_PENDING. Progress
is throttled, media queries run off the UI thread, and filesystem fallback
scans use asynchronous IO. The UI observes a durable native store, including
work started through the share dialog, and preserves legacy download history.

Pausing interrupts the extractor process and retains staging files. Resuming
re-extracts fresh URLs and asks yt-dlp to continue; some sites/segmented streams
may restart the transfer. MP3/M4A extraction uses FFmpeg rather than renaming
video containers. Best-video downloads prefer AVC/AAC and may use MKV when a
site only offers codecs that need it.

See THIRD_PARTY_NOTICES.md before public APK distribution.

## Delivered test build

The evaluation APK is built in release mode with native Java/Kotlin shrinking
disabled (`-Pshrink=false`) to stay within the build sandbox's memory limit.
Dart release/AOT optimizations remain enabled. On a configured checkout the
equivalent Gradle invocation is:

```sh
cd android
./gradlew :app:assembleRelease :app:testReleaseUnitTest -Ptarget-platform=android-arm64 -Psplit-per-abi=true -Pshrink=false --max-workers=1
```

Normal `flutter build apk --release` retains the standard R8 shrinking behavior.
