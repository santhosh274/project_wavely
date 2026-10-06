package com.wavely.app.wavely

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Extends AudioServiceActivity rather than FlutterActivity so the media session
 * can outlive the window: it is what lets playback continue while the app is
 * minimised or the screen is locked, and what publishes the notification.
 */
class MainActivity : AudioServiceActivity()
