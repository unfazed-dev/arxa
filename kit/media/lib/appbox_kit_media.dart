/// appbox_kit_media — "pixels and sound, in and out".
///
/// Framework-free ports for media capture and playback, backed by native
/// plugins. No dependency on stacked / appbox_kit: apps depend on this kit.
///
/// Ports:
/// * [AppBoxKitMediaCaptureService] — camera / library photo capture (typed results).
/// * [AppBoxKitAudioRecorderService] — recording with elapsed + amplitude streams.
/// * [AppBoxKitAudioPlayerService] — playback with position / duration / state streams.
/// * [AppBoxKitVideoPlayerService] — video playback (AVPlayer / ExoPlayer via
///   `video_player`) with a render surface ([AppBoxKitVideoPlayerService.videoView]).
/// * [AppBoxKitMediaEditingService] — phase-2A stub (editing / transcode).
///
/// See `package:appbox_kit_media/appbox_kit_testing.dart` for scriptable fakes.
library;

// Capture
export 'src/capture/appbox_kit_media_source.dart';
export 'src/capture/appbox_kit_media_capture_result.dart';
export 'src/capture/appbox_kit_media_capture_service.dart';

// Audio
export 'src/audio/appbox_kit_playback_state.dart';
export 'src/audio/appbox_kit_audio_recorder_service.dart';
export 'src/audio/appbox_kit_audio_player_service.dart';

// Video
export 'src/video/appbox_kit_video_player_service.dart';

// Editing / transcode (stub — phase 2A)
export 'src/editing/appbox_kit_media_editing_service.dart';
