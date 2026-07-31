# appbox_kit_media

**Pixels and sound, in and out.** Framework-free ports for media capture and
playback in `appbox_kit` apps, backed by thin wrappers over native
(AVFoundation / CameraX / ExoPlayer) plugins.

Phase 2A of the kit split.

## Scope

| Port | Backing | Status |
| --- | --- | --- |
| `MediaCaptureService` | `image_picker` | implemented — camera + library photo capture |
| `AudioRecorderService` | `record` | implemented — start/stop/cancel + elapsed & amplitude streams |
| `AudioPlayerService` | `just_audio` | implemented — load/play/pause/seek + position/duration/state streams |
| `VideoPlayerService` | `video_player` | implemented — load/play/pause/seek + streams + `videoView()` |
| `MediaEditingService` | ffmpeg/native (unwired) | **stub** — throws `UnimplementedError` |

Music and video **playback are absorbed here** — per the project decision there
are no separate `appbox_kit_music` / `appbox_kit_video` kits. Video playback
is the next port to implement against the existing `VideoPlayerService` seam.

## Design

- **No dependency on `stacked` / `stacked_services` / `appbox_kit`.** This kit
  is pure ports + backing plugins; apps depend on it, never the reverse.
- **No plugin type crosses a port.** `image_picker`'s `ImageSource`/`XFile`,
  `just_audio`'s `PlayerState`, and `record`'s `RecordConfig` stay inside the
  implementations. Callers see kit-owned `MediaSource`, `CapturedMedia`,
  `PlaybackState`.
- **Permission denial is a value, not an exception.** `capturePhoto` returns a
  sealed `MediaCaptureResult` (`MediaCaptured` / `MediaCaptureCancelled` /
  `MediaCapturePermissionDenied` / `MediaCaptureUnavailable` /
  `MediaCaptureFailed`) so callers `switch` exhaustively.
- **Capability flags:** `MediaCaptureService.hasCamera` (false on the iOS
  Simulator) lets UIs hide capture affordances that would fail.
- **The recorder owns its clock:** `elapsed$` emits `Duration.zero` on start,
  ticks while recording, and emits `null` when idle — bind directly instead of
  running a timer.

## Non-goals

- No UI. These are services; render chrome lives in the app.
- No permission-request orchestration beyond what the plugins do (a dedicated
  permissions kit owns explicit prompts).
- No file/organization policy — capture returns a temp file; the caller decides
  the durable location (`CapturedMedia.saveTo`).
- No transcoding/editing yet (`MediaEditingService` stub).

## Usage

```dart
import 'package:appbox_kit_media/appbox_kit_media.dart';

final capture = ImagePickerMediaCaptureService();
final result = await capture.capturePhoto(source: MediaSource.camera);
switch (result) {
  case MediaCaptured(:final media):
    await media.saveTo('/somewhere/photo.jpg');
  case MediaCapturePermissionDenied():
    // surface a "grant camera access" hint
  case MediaCaptureCancelled():
  case MediaCaptureUnavailable():
  case MediaCaptureFailed():
}
```

## Testing

`package:appbox_kit_media/testing.dart` ships scriptable fakes —
`FakeMediaCaptureService`, `FakeAudioRecorderService`, `FakeAudioPlayerService`
(and `FakeCapturedMedia`) — with canned files, scripted denial/failure, and
stream-driving helpers (`driveElapsed`, `drivePosition`, `driveState`, …). No
plugins or MethodChannels required.

## Host-app note

`record` / `just_audio` / `image_picker` pull the Windows FFI `win32` family
transitively. A host app that already depends on `talker_flutter`/`appwrite`
(as the showcase does) must keep the workspace `win32` / `device_info_plus` /
`package_info_plus` overrides — pub overrides do not propagate from this
package.
