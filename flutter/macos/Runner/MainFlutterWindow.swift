import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Below roughly this the board and the panel column stop being usable at
    // the same time — the layout's own wide breakpoint is 720.
    //
    // contentMinSize as well as minSize: minSize constrains the frame, but it
    // is contentMinSize that stops the Flutter view itself being squeezed,
    // and a window restored from a saved frame can come back smaller than
    // minSize alone would allow.
    let minContent = NSSize(width: 560, height: 620)
    self.contentMinSize = minContent
    self.minSize = self.frameRect(forContentRect: NSRect(origin: .zero, size: minContent)).size

    // Let the Flutter view own the whole window, titlebar included.
    //
    // The four settings the Flutter issue tracker's answer reaches for through
    // Interface Builder — they are ordinary window properties, so there is no
    // reason to open Xcode or edit a XIB for them:
    //
    //   fullSizeContentView   the content view extends under the titlebar
    //   titlebarAppearsTransparent  no bar chrome drawn over it
    //   titleVisibility = .hidden   no window title text
    //   isMovableByWindowBackground drag the window by its content, since
    //                               there is no longer a bar to grab
    //
    // The traffic lights stay — they are the system's, they respect the user's
    // settings, and reimplementing them means reimplementing hover states,
    // full-screen behaviour and accessibility for no gain. What changes is
    // that they now float over the app's own app bar, which is why the Dart
    // side insets its leading edge on macOS (see kMacTitlebarInset).
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
