# arxa_kit_media

**Pixels and sound, in and out.** Framework-free ports for media capture and
playback in `arxa_kit` apps, backed by thin wrappers over native
(AVFoundation / CameraX / ExoPlayer) plugins.

Phase 2A of the kit split.

## Scope

| Port | Backing | Status |
| --- | --- | --- |
| `ArxaKitMediaCaptureService` | `image_picker` | implemented — camera + library photo capture |
| `ArxaKitAudioRecorderService` | `record` | implemented — start/stop/cancel + elapsed & amplitude streams |
| `ArxaKitAudioPlayerService` | `just_audio` | implemented — load/play/pause/seek + position/duration/state streams |
| `ArxaKitVideoPlayerService` | `video_player` | implemented — load/play/pause/seek + streams + `videoView()` |
| `ArxaKitMediaEditingService` | ffmpeg/native (unwired) | **stub** — throws `UnimplementedError` |

Music and video **playback are absorbed here** — per the project decision there
are no separate `arxa_kit_music` / `arxa_kit_video` kits. Video playback
is the next port to implement against the existing `ArxaKitVideoPlayerService` seam.

## Design

- **No dependency on `stacked` / `stacked_services` / `arxa_kit`.** This kit
  is pure ports + backing plugins; apps depend on it, never the reverse.
- **No plugin type crosses a port.** `image_picker`'s `ImageSource`/`XFile`,
  `just_audio`'s `PlayerState`, and `record`'s `RecordConfig` stay inside the
  implementations. Callers see kit-owned `ArxaKitMediaSource`, `ArxaKitCapturedMedia`,
  `ArxaKitPlaybackState`.
- **Permission denial is a value, not an exception.** `capturePhoto` returns a
  sealed `ArxaKitMediaCaptureResult` (`ArxaKitMediaCaptured` / `ArxaKitMediaCaptureCancelled` /
  `ArxaKitMediaCapturePermissionDenied` / `ArxaKitMediaCaptureUnavailable` /
  `ArxaKitMediaCaptureFailed`) so callers `switch` exhaustively.
- **Capability flags:** `ArxaKitMediaCaptureService.hasCamera` (false on the iOS
  Simulator) lets UIs hide capture affordances that would fail.
- **The recorder owns its clock:** `elapsed$` emits `Duration.zero` on start,
  ticks while recording, and emits `null` when idle — bind directly instead of
  running a timer.

## Non-goals

- No UI. These are services; render chrome lives in the app.
- No permission-request orchestration beyond what the plugins do (a dedicated
  permissions kit owns explicit prompts).
- No file/organization policy — capture returns a temp file; the caller decides
  the durable location (`ArxaKitCapturedMedia.saveTo`).
- No transcoding/editing yet (`ArxaKitMediaEditingService` stub).

## Usage

```dart
import 'package:arxa_kit_media/arxa_kit_media.dart';

final capture = ArxaKitImagePickerMediaCaptureService();
final result = await capture.capturePhoto(source: ArxaKitMediaSource.camera);
switch (result) {
  case ArxaKitMediaCaptured(:final media):
    await media.saveTo('/somewhere/photo.jpg');
  case ArxaKitMediaCapturePermissionDenied():
    // surface a "grant camera access" hint
  case ArxaKitMediaCaptureCancelled():
  case ArxaKitMediaCaptureUnavailable():
  case ArxaKitMediaCaptureFailed():
}
```

## Testing

`package:arxa_kit_media/arxa_kit_testing.dart` ships scriptable fakes —
`FakeArxaKitMediaCaptureService`, `FakeArxaKitAudioRecorderService`, `FakeArxaKitAudioPlayerService`
(and `FakeArxaKitCapturedMedia`) — with canned files, scripted denial/failure, and
stream-driving helpers (`driveElapsed`, `drivePosition`, `driveState`, …). No
plugins or MethodChannels required.

## Host-app note

`record` / `just_audio` / `image_picker` pull the Windows FFI `win32` family
transitively. A host app that already depends on `talker_flutter`/`appwrite`
(as the showcase does) must keep the workspace `win32` / `device_info_plus` /
`package_info_plus` overrides — pub overrides do not propagate from this
package.
