/// arxa_kit_media — "pixels and sound, in and out".
///
/// Framework-free ports for media capture and playback, backed by native
/// plugins. No dependency on stacked / arxa_kit: apps depend on this kit.
///
/// Ports:
/// * [ArxaKitMediaCaptureService] — camera / library photo capture (typed results).
/// * [ArxaKitAudioRecorderService] — recording with elapsed + amplitude streams.
/// * [ArxaKitAudioPlayerService] — playback with position / duration / state streams.
/// * [ArxaKitVideoPlayerService] — video playback (AVPlayer / ExoPlayer via
///   `video_player`) with a render surface ([ArxaKitVideoPlayerService.videoView]).
/// * [ArxaKitMediaEditingService] — phase-2A stub (editing / transcode).
///
/// See `package:arxa_kit_media/arxa_kit_testing.dart` for scriptable fakes.
library;

// Capture
export 'src/capture/arxa_kit_media_source.dart';
export 'src/capture/arxa_kit_media_capture_result.dart';
export 'src/capture/arxa_kit_media_capture_service.dart';

// Audio
export 'src/audio/arxa_kit_playback_state.dart';
export 'src/audio/arxa_kit_audio_recorder_service.dart';
export 'src/audio/arxa_kit_audio_player_service.dart';

// Video
export 'src/video/arxa_kit_video_player_service.dart';

// Editing / transcode (stub — phase 2A)
export 'src/editing/arxa_kit_media_editing_service.dart';
