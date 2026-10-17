# Wavely

A local music player built with Flutter. It reads the audio already on the
device, groups it into albums, artists and playlists, and plays it back.

## Features

- Scans the device media store for audio files (Android `MediaStore`, iOS
  `MPMediaQuery`)
- Library browser with Songs / Albums / Artists / Playlists tabs and search
- Playlists generated from the genres present on the device
- Playback with just_audio, plus a mini player and full-screen now playing view
- Light and dark themes

## Permissions

Reading local audio needs a runtime permission, which is requested on first
launch and can be re-granted from the in-app prompt or the OS settings page.

| Platform | Permission |
| --- | --- |
| Android 13+ (API 33) | `READ_MEDIA_AUDIO` |
| Android 12 and below | `READ_EXTERNAL_STORAGE` |
| Android (playback) | `MODIFY_AUDIO_SETTINGS` |
| Android (listening rooms) | `INTERNET` |
| Android 17+ (API 37, listening rooms) | `ACCESS_LOCAL_NETWORK` |
| iOS | `NSAppleMusicUsageDescription`, `NSLocalNetworkUsageDescription` |

`INTERNET` is a normal permission: Android grants it at install and never shows
a prompt, so its absence from the runtime list is expected. The one network
permission that is asked for is `ACCESS_LOCAL_NETWORK`, and only builds
targeting SDK 37 have to ask -- which this app does (`targetSdk = 37` in
`android/app/build.gradle.kts`). On a lower target Android grants local-network
access implicitly through `INTERNET` and shows nothing, which is why the prompt
never appeared before. On iOS the local-network prompt is raised by the system
on first LAN access rather than from the app.

On Android, `permission_handler` needs macro definitions in the iOS `Podfile`
to compile its permission code. Without them the app still builds, but
`Permission.audio` calls fail silently on iOS.

## Running

```bash
flutter pub get
flutter run
```

## Notes

`on_audio_query_android` 1.1.0 is the latest release and predates AGP 8, so
`android/build.gradle.kts` contains compatibility shims that give plugin library
modules a `namespace`, align their JVM targets, and raise their `compileSdk`.
Those shims are documented inline.
