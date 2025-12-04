import AppKit

struct AppInfo: Identifiable, Equatable, Hashable {
   let id: UUID
   let name: String
   let icon: NSImage
   let path: String
   let bundleId: String
   let lastOpenedDate: Date?
   let installDate: Date?
   var page: Int
   var openCount: Int

   init(name: String, icon: NSImage, path: String, bundleId: String, lastOpenedDate: Date?, installDate: Date?, page: Int = 0, openCount: Int = 0) {
      self.id = UUID()
      self.name = name
      self.icon = icon
      self.path = path
      self.bundleId = bundleId
      self.lastOpenedDate = lastOpenedDate
      self.installDate = installDate
      self.page = page
      self.openCount = openCount
   }
}
