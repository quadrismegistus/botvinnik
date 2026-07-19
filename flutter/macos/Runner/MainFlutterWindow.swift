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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
