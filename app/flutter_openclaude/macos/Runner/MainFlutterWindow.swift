import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWorkspaceChannel(flutterViewController)

    super.awakeFromNib()
  }

  private func registerWorkspaceChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "openclaude/workspace",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickProjectDirectory(result)
    }
  }

  private func pickProjectDirectory(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.message = "Choose a project directory"
      panel.prompt = "Open"

      let completion: (NSApplication.ModalResponse) -> Void = { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        result(url.path)
      }

      if let window = self {
        panel.beginSheetModal(for: window, completionHandler: completion)
      } else {
        completion(panel.runModal())
      }
    }
  }
}
