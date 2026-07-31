import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_media/testing.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('PluginVideoPlayerService.toState', () {
    test('uninitialized maps to loading, not playing', () {
      final state = PluginVideoPlayerService.toState(
        const VideoPlayerValue.uninitialized(),
      );
      expect(state.processing, MediaProcessingState.loading);
      expect(state.playing, isFalse);
    });

    test('buffering wins over ready once initialized', () {
      final state = PluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isPlaying: true,
          isBuffering: true,
        ),
      );
      expect(state.processing, MediaProcessingState.buffering);
      expect(state.playing, isTrue);
    });

    test('initialized mid-play maps to ready', () {
      final state = PluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 3),
          isInitialized: true,
          isPlaying: true,
        ),
      );
      expect(state.processing, MediaProcessingState.ready);
      expect(state.playing, isTrue);
    });

    test('paused at the end maps to completed', () {
      final state = PluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 10),
          isInitialized: true,
        ),
      );
      expect(state.processing, MediaProcessingState.completed);
      expect(state.isCompleted, isTrue);
    });

    test('plugin isCompleted flag alone maps to completed', () {
      final state = PluginVideoPlayerService.toState(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isCompleted: true,
        ),
      );
      expect(state.processing, MediaProcessingState.completed);
    });
  });

  group('FakeVideoPlayerService', () {
    test('records loads and drives play/pause state', () async {
      final fake = FakeVideoPlayerService();
      final states = <PlaybackState>[];
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

    test('stop rewinds position to zero', () async {
      final fake = FakeVideoPlayerService();
      final positions = <Duration>[];
      final sub = fake.position$.listen(positions.add);

      await fake.seek(const Duration(seconds: 4));
      await fake.stop();

      expect(positions, [const Duration(seconds: 4), Duration.zero]);
      await sub.cancel();
      await fake.dispose();
    });
  });

  test('StubVideoPlayerService fails loudly', () {
    final stub = StubVideoPlayerService();
    expect(() => stub.position$, throwsUnimplementedError);
    expect(() => stub.videoView(), throwsUnimplementedError);
    expect(() => stub.play(), throwsUnimplementedError);
  });
}
