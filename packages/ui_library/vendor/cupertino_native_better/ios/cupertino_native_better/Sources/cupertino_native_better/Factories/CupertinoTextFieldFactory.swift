import Flutter
import UIKit

/// Factory for [CupertinoTextFieldPlatformView]. Mirrors
/// [CupertinoSearchBarFactory] — the only difference is the platform view type
/// it constructs and the `"CNTextField"` viewType registered in the plugin.
public class CupertinoTextFieldFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    public init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    public func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return CupertinoTextFieldPlatformView(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }
}
