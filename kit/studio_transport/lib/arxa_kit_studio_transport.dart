/// iroh-backed pairing transport for arxa studio mobile.
///
/// Real transport: [StudioTransport.connect]. Test double:
/// [MockStudioSession] / [MockStudioTransport].
library;

export 'src/mock_transport.dart';
export 'src/studio_transport.dart'
    show StudioSession, StudioSessionStatus, StudioTransport;
