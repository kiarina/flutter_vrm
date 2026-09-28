import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Always open 1280x800 on the primary display (the one with the menu
    // bar). A frame restored onto a sleeping secondary display stops vsync,
    // and SceneView then stops ticking, which ruins measurements.
    self.isRestorable = false
    let primary = NSScreen.screens.first?.visibleFrame ?? self.frame
    let size = NSSize(width: 1280, height: 800)
    let origin = NSPoint(x: primary.midX - size.width / 2,
                         y: primary.midY - size.height / 2)
    self.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}
