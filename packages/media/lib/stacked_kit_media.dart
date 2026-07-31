/// appbox_kit_media — "pixels and sound, in and out".
///
/// Framework-free ports for media capture and playback, backed by native
/// plugins. No dependency on stacked / stacked_kit: apps depend on this kit.
///
/// Ports:
/// * [MediaCaptureService] — camera / library photo capture (typed results).
/// * [AudioRecorderService] — recording with elapsed + amplitude streams.
/// * [AudioPlayerService] — playback with position / duration / state streams.
/// * [VideoPlayerService] — video playback (AVPlayer / ExoPlayer via
///   `video_player`) with a render surface ([VideoPlayerService.videoView]).
/// * [MediaEditingService] — phase-2A stub (editing / transcode).
///
/// See `package:appbox_kit_media/testing.dart` for scriptable fakes.
library;

// Capture
export 'src/capture/media_source.dart';
export 'src/capture/media_capture_result.dart';
export 'src/capture/media_capture_service.dart';

// Audio
export 'src/audio/playback_state.dart';
export 'src/audio/audio_recorder_service.dart';
export 'src/audio/audio_player_service.dart';

// Video
export 'src/video/video_player_service.dart';

// Editing / transcode (stub — phase 2A)
export 'src/editing/media_editing_service.dart';
