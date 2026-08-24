import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Headless background refresh: keep the engine running (plugins work) but
    // never show a window or steal focus, then the Dart side exits.
    if CommandLine.arguments.contains("--headless") {
      self.orderOut(nil)
      NSApp.setActivationPolicy(.prohibited)
    }
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    if CommandLine.arguments.contains("--headless") { return }
    super.makeKeyAndOrderFront(sender)
  }
}
