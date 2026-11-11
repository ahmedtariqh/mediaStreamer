# Download engine dependencies

The Android downloader links youtubedl-android library/FFmpeg 0.18.1
(https://github.com/yausername/youtubedl-android), licensed GPL-3.0.
The distribution includes yt-dlp, Python, QuickJS and FFmpeg components with
separate upstream notices and licenses. See the upstream source and published
artifacts for the complete licenses and corresponding source.

The repository's original MediaStreamer Non-Commercial License has not been
changed. That restriction is not compatible with GPL distribution of the linked
application. Resolve the app's distribution license and corresponding-source
obligations before publicly distributing APKs built with these dependencies.
This branch and its test APK are intended for the owner's evaluation.

Extractor updates are fetched from the official yt-dlp GitHub releases over
HTTPS and verified against the release asset's SHA-256 digest before replacing
the installed engine. Failures retain the installed extractor.

## Playback engine

LibVLC Android 3.7.5 is distributed by VideoLAN under LGPL-2.1-or-later.
This app links the published libvlc-all artifact; it does not copy VLC Android
artwork, name, application code or assets. VideoLAN source and license:
https://code.videolan.org/videolan/vlc-android/-/tree/master/libvlc
https://github.com/videolan/vlc/blob/3.0.x/COPYING.LIB
The complete app source and reproducible dependency versions are provided in
this repository. Retain all upstream notices with distributions. This addition
does not resolve the pre-existing GPL/non-commercial license conflict above.
