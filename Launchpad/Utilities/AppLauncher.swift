import AppKit

@MainActor
final class AppLauncher {
   static func launch(path: String) {
      AppManager.shared.incrementOpenCount(forPath: path)
      NSWorkspace.shared.open(URL(fileURLWithPath: path))
      exit()
   }
   
   static func exit() {
      print("Exiting Launchpad.")
      NSApp.hide(nil)
   }
}
