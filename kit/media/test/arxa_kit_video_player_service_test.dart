import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_media/arxa_kit_media.dart';
import 'package:arxa_kit_media/arxa_kit_testing.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('ArxaKitPluginVideoPlayerService.toState', () {
    test('kit.media.video-player — uninitialized maps to loading, not playing', () {
      final state = ArxaKitPluginVideoPlayerService.toState(
        const VideoPlayerValue.uninitialized(),
      );
      expect(state.processing, ArxaKitMediaProcessingState.loading);
      expect(state.playing, isFalse);
    });

    test('kit.media.video-player — buffering wins over ready once initialized', () {
      final state = ArxaKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isPlaying: true,
          isBuffering: true,
        ),
      );
      expect(state.processing, ArxaKitMediaProcessingState.buffering);
      expect(state.playing, isTrue);
    });

    test('kit.media.video-player — initialized mid-play maps to ready', () {
      final state = ArxaKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 3),
          isInitialized: true,
          isPlaying: true,
        ),
      );
      expect(state.processing, ArxaKitMediaProcessingState.ready);
      expect(state.playing, isTrue);
    });

    test('kit.media.video-player — paused at the end maps to completed', () {
      final state = ArxaKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 10),
          isInitialized: true,
        ),
      );
      expect(state.processing, ArxaKitMediaProcessingState.completed);
      expect(state.isCompleted, isTrue);
    });

    test('kit.media.video-player — plugin isCompleted flag alone maps to completed', () {
      final state = ArxaKitPluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isCompleted: true,
        ),
      );
      expect(state.processing, ArxaKitMediaProcessingState.completed);
    });
  });

  group('FakeArxaKitVideoPlayerService', () {
    test('kit.media.video-player — records loads and drives play/pause state', () async {
      final fake = FakeArxaKitVideoPlayerService();
      final states = <ArxaKitPlaybackState>[];
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
      final fake = FakeArxaKitVideoPlayerService();
      final positions = <Duration>[];
      final sub = fake.position$.listen(positions.add);

      await fake.seek(const Duration(seconds: 4));
      await fake.stop();

      expect(positions, [const Duration(seconds: 4), Duration.zero]);
      await sub.cancel();
      await fake.dispose();
    });
  });

  test('kit.media.video-player — ArxaKitStubVideoPlayerService fails loudly', () {
    final stub = ArxaKitStubVideoPlayerService();
    expect(() => stub.position$, throwsUnimplementedError);
    expect(() => stub.videoView(), throwsUnimplementedError);
    expect(() => stub.play(), throwsUnimplementedError);
  });
}
