import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_media/appbox_kit_testing.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('AppBoxKitPluginVideoPlayerService.toState', () {
    test('kit.media.video-player — uninitialized maps to loading, not playing', () {
      final state = AppBoxKitPluginVideoPlayerService.toState(
        const VideoPlayerValue.uninitialized(),
      );
      expect(state.processing, AppBoxKitMediaProcessingState.loading);
      expect(state.playing, isFalse);
    });

    test('kit.media.video-player — buffering wins over ready once initialized', () {
      final state = AppBoxKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isPlaying: true,
          isBuffering: true,
        ),
      );
      expect(state.processing, AppBoxKitMediaProcessingState.buffering);
      expect(state.playing, isTrue);
    });

    test('kit.media.video-player — initialized mid-play maps to ready', () {
      final state = AppBoxKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 3),
          isInitialized: true,
          isPlaying: true,
        ),
      );
      expect(state.processing, AppBoxKitMediaProcessingState.ready);
      expect(state.playing, isTrue);
    });

    test('kit.media.video-player — paused at the end maps to completed', () {
      final state = AppBoxKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 10),
          isInitialized: true,
        ),
      );
      expect(state.processing, AppBoxKitMediaProcessingState.completed);
      expect(state.isCompleted, isTrue);
    });

    test('kit.media.video-player — plugin isCompleted flag alone maps to completed', () {
      final state = AppBoxKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isCompleted: true,
        ),
      );
      expect(state.processing, AppBoxKitMediaProcessingState.completed);
    });
  });

  group('FakeAppBoxKitVideoPlayerService', () {
    test('kit.media.video-player — records loads and drives play/pause state', () async {
      final fake = FakeAppBoxKitVideoPlayerService();
      final states = <AppBoxKitPlaybackState>[];
      final sub = fake.state$.listen(states.add);

      await fake.load('a.mp4');
      await fake.load('https://x.test/b.mp4');
      await fake.play();
      await fake.pause();

      expect(fake.loadedSources, ['a.mp4', 'https://x.test/b.mp4']);
      expect(states.map((s) => s.playing), [true, false]);
      await sub.cancel();
      await fake.dispose();
    });

    test('kit.media.video-player — stop rewinds position to zero', () async {
      final fake = FakeAppBoxKitVideoPlayerService();
      final positions = <Duration>[];
      final sub = fake.position$.listen(positions.add);

      await fake.seek(const Duration(seconds: 4));
      await fake.stop();

      expect(positions, [const Duration(seconds: 4), Duration.zero]);
      await sub.cancel();
      await fake.dispose();
    });
  });

  test('kit.media.video-player — AppBoxKitStubVideoPlayerService fails loudly', () {
    final stub = AppBoxKitStubVideoPlayerService();
    expect(() => stub.position$, throwsUnimplementedError);
    expect(() => stub.videoView(), throwsUnimplementedError);
    expect(() => stub.play(), throwsUnimplementedError);
  });
}
