import SwiftUI

extension AppGridItem {
   var path: String {
      switch self {
      case .app(let app): return app.path
      case .folder: return ""
      case .category: return ""
      }
   }

   var lastOpenedDate: Date? {
      switch self {
      case .app(let app): return app.lastOpenedDate
      case .folder(let folder): return folder.apps.compactMap(\.lastOpenedDate).max()
      case .category: return nil
      }
   }

   var installDate: Date? {
      switch self {
      case .app(let app): return app.installDate
      case .folder(let folder): return folder.apps.compactMap(\.installDate).max()
      case .category: return nil
      }
   }

   var openCount: Int {
      switch self {
      case .app(let app): return app.openCount
      case .folder(let folder): return folder.apps.map(\.openCount).reduce(0, +)
      case .category: return 0
      }
   }

   var appPaths: Set<String> {
      switch self {
      case .app(let app): return [app.path]
      case .folder(let folder): return Set(folder.apps.map(\.path))
      case .category: return []
      }
   }

   func serialize() -> [String: Any] {
      switch self {
      case .app(let app): return serialize(app)
      case .folder(let folder): return serialize(folder)
      case .category: return [:]
      }
   }

   func serialize(_ folder: Folder) -> [String : Any] {
      return [
         "type": "folder",
         "id": folder.id.uuidString,
         "name": folder.name,
         "page": folder.page,
         "apps": folder.apps.map(serialize)
      ]
   }

   func serialize(_ app: AppInfo) -> [String: Any] {
      [
         "type": "app",
         "id": app.id.uuidString,
         "name": app.name,
         "page": app.page,
         "path": app.path,
         "openCount": app.openCount
      ]
   }

   func withUpdatedPage(_ newPage: Int) -> AppGridItem {
      switch self {
      case .app(let app):
         return .app(AppInfo(name: app.name, icon: app.icon, path: app.path, bundleId: app.bundleId, lastOpenedDate: app.lastOpenedDate, installDate: app.installDate, page: newPage, openCount: app.openCount))
      case .folder(let folder):
         return .folder(Folder(name: folder.name, page: newPage, apps: folder.apps))
      case .category(let category):
         return .category(category)
      }
   }
}
