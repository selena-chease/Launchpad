import AppKit
import Foundation

@MainActor
final class AppManager: ObservableObject {
   private let importManager = DatabaseImportManager.shared
   private let settingsManager = SettingsManager.shared
   private let iconManager = IconCacheManager.shared
   private let fileManager = FileManager.default
   
   private let userDefaults = UserDefaults.standard
   private let gridItemsKey = "LaunchpadAppGridItems"
   private let hiddenAppsKey = "LaunchpadHiddenApps"
   
   static let shared = AppManager()
   
   private init() {
      self.pages = [[]]
      self.hiddenAppPaths = Set(userDefaults.stringArray(forKey: hiddenAppsKey) ?? [])
   }
   
   @Published var pages: [[AppGridItem]]
   @Published var hiddenAppPaths: Set<String> {
      didSet {
         saveHiddenApps()
      }
   }
   
   func loadAppGridItems(appsPerPage: Int) {
      print("Load grid items.")
      let apps = discoverApps()
      let gridItems = loadLayoutFromUserDefaults(for: apps)
      pages = groupItemsByPage(items: gridItems, appsPerPage: appsPerPage)
   }
   
   func saveAppGridItems() {
      print("Save grid items.")
      let itemsData = pages.flatMap { $0 }.map { $0.serialize() }
      userDefaults.set(itemsData, forKey: gridItemsKey)
   }
   
   func importLayout(appsPerPage: Int) -> (success: Bool, message: String) {
      let filePath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("LaunchpadLayout.json")
      let result = importLayoutFromJSON(filePath: filePath, appsPerPage: appsPerPage)
      saveAppGridItems()
      return result
   }
   
   func exportLayout() -> (success: Bool, message: String) {
      let filePath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("LaunchpadLayout.json")
      return exportLayoutToJSON(filePath: filePath)
   }
   
   func clearAppGridItems(appsPerPage: Int) {
      print("Clear grid items.")
      userDefaults.removeObject(forKey: gridItemsKey)
      loadAppGridItems(appsPerPage: appsPerPage)
   }
   
   func refreshApps(appsPerPage: Int) {
      print("Refresh apps.")
      let apps = discoverApps()
      let gridItems = loadLayoutFromUserDefaults(for: apps)
      pages = groupItemsByPage(items: gridItems, appsPerPage: appsPerPage)
      saveAppGridItems()
   }
   
   func importFromOldLaunchpad(appsPerPage: Int) -> Bool {
      print("Import from old Launchpad database.")
      let apps = discoverApps()
      
      guard importManager.oldLaunchpadDatabaseExists() else {
         print("Old Launchpad database not found")
         return false
      }
      
      var gridItems = importManager.readOldLaunchpadLayout(currentApps: apps)
      addRemainingApps(items: &gridItems, apps: apps)
      pages = groupItemsByPage(items: gridItems, appsPerPage: appsPerPage)
      saveAppGridItems()
      
      print("Successfully imported layout from old Launchpad")
      return true
   }
   
   func recalculatePages(appsPerPage: Int) {
      print("Recalculate pages.")
      let allItems = pages.flatMap { $0 }
      pages = groupItemsByPage(items: allItems, appsPerPage: appsPerPage)
   }
   
   func sortItems(by sortOrder: SortOrder, appsPerPage: Int) {
      var allItems = pages.flatMap { $0 }
      
      switch sortOrder {
      case .name:
         allItems = sortByName(allItems)
      case .itemType:
         allItems = sortByType(allItems)
      case .lastOpened:
         allItems = sortByLastOpened(allItems)
      case .installDate:
         allItems = sortByInstallDate(allItems)
      case .mostOpened:
         allItems = sortByMostOpened(allItems)
      case .defaultLayout:
         allItems = loadLayoutFromUserDefaults(for: discoverApps())
      }
      
      // Reset page numbers to 0 for proper redistribution when not using default layout
      if sortOrder != .defaultLayout {
         allItems = allItems.map { $0.withUpdatedPage(0) }
      }
      
      pages = groupItemsByPage(items: allItems, appsPerPage: appsPerPage)
   }
   
   fileprivate func sortByName(_ items: [AppGridItem]) -> [AppGridItem] {
      return items.sorted { $0.name < $1.name }
   }
   
   fileprivate func sortByType(_ items: [AppGridItem]) -> [AppGridItem] {
      return items.sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name < $1.name }
   }
   
   fileprivate func sortByLastOpened(_ items: [AppGridItem]) -> [AppGridItem] {
      return items.sorted { sortByDate($0, $1, keyPath: \.lastOpenedDate) }
   }
   
   fileprivate func sortByInstallDate(_ items: [AppGridItem]) -> [AppGridItem] {
      return items.sorted { sortByDate($0, $1, keyPath: \.installDate) }
   }
   
   fileprivate func sortByMostOpened(_ items: [AppGridItem]) -> [AppGridItem] {
      return items.sorted { sortByCount($0, $1) }
   }
   
   private func sortByCount(_ item1: AppGridItem, _ item2: AppGridItem) -> Bool {
      let count1 = item1.openCount
      let count2 = item2.openCount
      
      // If both have counts, compare them (higher first)
      if count1 > 0 && count2 > 0 {
         if count1 != count2 {
            return count1 > count2
         }
         // If counts are equal, sort by name
         return item1.name < item2.name
      }
      // If only first has count, it comes first
      if count1 > 0 { return true }
      // If only second has count, it comes first
      if count2 > 0 { return false }
      // If neither has count, sort by name
      return item1.name < item2.name
   }
   
   private func sortByDate(_ item1: AppGridItem, _ item2: AppGridItem, keyPath: KeyPath<AppGridItem, Date?>) -> Bool {
      let date1 = item1[keyPath: keyPath]
      let date2 = item2[keyPath: keyPath]
      
      // If both have dates, compare them (newer first)
      if let d1 = date1, let d2 = date2 {
         return d1 > d2
      }
      // If only first has date, it comes first
      if date1 != nil { return true }
      // If only second has date, it comes first
      if date2 != nil { return false }
      // If neither has date, sort by name
      return item1.name < item2.name
   }
   
   private func discoverApps() -> [AppInfo] {
      print("Discover apps.")
      let defaultPaths = ["/Applications", "/System/Applications"]
      let customPaths = settingsManager.settings.customAppLocations
      let allPaths = defaultPaths + customPaths
      return allPaths.flatMap { discoverAppsRecursively(directory: $0) }.sorted { $0.name.lowercased() < $1.name.lowercased() }
   }
   
   private func discoverAppsRecursively(directory: String, maxDepth: Int = 3, currentDepth: Int = 0) -> [AppInfo] {
      guard currentDepth < maxDepth, let contents = try? fileManager.contentsOfDirectory(atPath: directory)
      else { return [] }
      var foundApps: [AppInfo] = []
      for item in contents {
         let path = "\(directory)/\(item)"
         if item.hasSuffix(".app") {
            let url = URL(fileURLWithPath: path)
            let name = getLocalizedAppName(for: url, fallbackName: item.replacingOccurrences(of: ".app", with: ""))
            let icon = iconManager.icon(forPath: path)
            let bundleId = Bundle(path: path)?.bundleIdentifier ?? "unknown.bundle.\(name)"
            let (installDate, lastOpenedDate) = getAppDates(url: url)
            foundApps.append(AppInfo(name: name, icon: icon, path: path, bundleId: bundleId, lastOpenedDate: lastOpenedDate, installDate: installDate))
         } else if shouldSearchDirectory(item: item, at: path) {
            foundApps.append(contentsOf: discoverAppsRecursively(directory: path, maxDepth: maxDepth, currentDepth: currentDepth + 1))
         }
      }
      return foundApps
   }
   
   private func shouldSearchDirectory(item: String, at path: String) -> Bool {
      let skipDirectories = [".Trash", ".DS_Store", ".localized"]
      var isDirectory: ObjCBool = false
      return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue && !skipDirectories.contains(item) && !item.hasPrefix(".")
   }
   
   private func getAppDates(url: URL) -> (installDate: Date?, lastOpenedDate: Date?) {
      if let metadataItem = NSMetadataItem(url: url) {
         let addedDate = metadataItem.value(forAttribute: kMDItemDateAdded as String) as? Date
         let lastUsedDate = metadataItem.value(forAttribute: kMDItemLastUsedDate as String) as? Date
         return (addedDate, lastUsedDate)
      }
      return (nil, nil)
   }
   
   private func loadLayoutFromUserDefaults(for apps: [AppInfo]) -> [AppGridItem] {
      print("Load layout.")
      guard let savedData = userDefaults.array(forKey: gridItemsKey) as? [[String: Any]] else {
         return apps.map { .app($0) }
      }
      
      let appsByPath = Dictionary(uniqueKeysWithValues: apps.unique(by: \.path).map { ($0.path, $0) })
      var gridItems = parseAppGridItems(from: savedData, appsByPath: appsByPath)
      addRemainingApps(items: &gridItems, apps: apps)
      return gridItems
   }
   
   private func parseAppGridItems(from itemsArray: [[String: Any]], appsByPath: [String: AppInfo]) -> [AppGridItem] {
      var gridItems: [AppGridItem] = []

      for itemData in itemsArray {
         guard let type = itemData["type"] as? String else { continue }
         switch type {
         case "app":
            if let gridItem = loadApp(from: itemData, appsByPath: appsByPath) {
               gridItems.append(.app(gridItem))
            }
         case "folder":
            if let gridItem = loadFolder(from: itemData, appsByPath: appsByPath) {
               gridItems.append(.folder(gridItem))
            }
         default:
            break
         }
      }
      
      return gridItems
   }
   
   private func loadApp(from itemData: [String: Any], appsByPath: [String: AppInfo]) -> AppInfo? {
      let path = itemData["path"] as! String
      let page = itemData["page"] as! Int
      let openCount = itemData["openCount"] as? Int ?? 0
      guard let baseApp = appsByPath[path] else { return nil }
      return AppInfo(name: baseApp.name, icon: baseApp.icon, path: baseApp.path, bundleId: baseApp.bundleId,lastOpenedDate: baseApp.lastOpenedDate, installDate: baseApp.installDate, page: page, openCount: openCount)
   }
   
   private func loadFolder(from itemData: [String: Any], appsByPath: [String: AppInfo]) -> Folder? {
      let folderName = itemData["name"] as! String
      let savedPage = itemData["page"] as? Int ?? 0
      let appsData = itemData["apps"] as! [[String: Any]]
      
      let folderApps = appsData.compactMap { loadApp(from: $0, appsByPath: appsByPath)}
      
      guard !folderApps.isEmpty else { return nil }
      return Folder(name: folderName, page: savedPage, apps: folderApps)
   }
   
   private func getLocalizedAppName(for url: URL, fallbackName: String) -> String {
      if let rawValue = NSMetadataItem(url: url)?.value(forAttribute: kMDItemDisplayName as String) as? String {
         var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
         if trimmed.lowercased().hasSuffix(".app") {
            trimmed = String(trimmed.dropLast(4))
         }
         return trimmed
      }
      return fallbackName
   }
   
   private func groupItemsByPage(items: [AppGridItem], appsPerPage: Int) -> [[AppGridItem]] {
      let groupedByPage = Dictionary(grouping: items.filter { item in !isItemHidden(item) }.uniqueOrDefault(by: \.path)) { $0.page }
      let pageCount = max(groupedByPage.keys.max() ?? 1, 1)
      var pages: [[AppGridItem]] = []
      var currentPage = 0
      
      for pageNum in currentPage...pageCount {
         currentPage = pageNum
         var currentPageItems: [AppGridItem] = []
         let pageItems = groupedByPage[pageNum] ?? []
         for item in pageItems {
            if currentPageItems.count >= appsPerPage {
               pages.append(currentPageItems)
               currentPage += 1
               currentPageItems = []
            }
            
            let updatedItem = currentPage > item.page ? item.withUpdatedPage(currentPage) : item
            currentPageItems.append(updatedItem)
         }
         
         if !currentPageItems.isEmpty {
            pages.append(currentPageItems)
         }
      }
      return pages.isEmpty ? [[]] : pages
   }
   
   private func importLayoutFromJSON(filePath: URL, appsPerPage: Int) -> (success: Bool, message: String) {
      guard fileManager.fileExists(atPath: filePath.path) else {
         print("Layout file not found at \(filePath.path)")
         return (false, "Layout file not found at \n\(filePath.path)")
      }
      
      do {
         let jsonData = try Data(contentsOf: filePath)
         guard let itemsArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return (false, "Invalid JSON format")
         }
         
         let apps = discoverApps()
         let appsByPath = Dictionary(uniqueKeysWithValues: apps.unique(by: \.path).map { ($0.path, $0) })
         var gridItems = parseAppGridItems(from: itemsArray, appsByPath: appsByPath)
         addRemainingApps(items: &gridItems, apps: apps)
         pages = groupItemsByPage(items: gridItems, appsPerPage: appsPerPage)
         
         print("Successfully imported layout from \(filePath.path)")
         return (true, "Successfully imported layout from \n\(filePath.path)")
      } catch {
         print("Failed to import layout \(error)")
         return (false, "Failed to import layout \n\(error.localizedDescription)")
      }
   }
   
   private func exportLayoutToJSON(filePath: URL) -> (success: Bool, message: String) {
      do {
         let itemsData = pages.flatMap { $0 }.map { $0.serialize() }
         let jsonData = try JSONSerialization.data(withJSONObject: itemsData, options: .prettyPrinted)
         try jsonData.write(to: filePath)
         print("Layout export finished successfully to \(filePath.path)")
         return (true, "Layout export finished successfully to \n\(filePath.path)")
      } catch {
         print("Failed to export layout \(error)")
         return (false, "Failed to export layout \n\(error.localizedDescription)")
      }
   }
   
   private func addRemainingApps(items: inout [AppGridItem], apps: [AppInfo]) {
      var usedApps = Set<String>()
      for gridItem in items {
         usedApps.formUnion(gridItem.appPaths)
      }
      
      let maxPage = items.map(\.page).max() ?? 0
      for app in apps where !usedApps.contains(app.path) {
         items.append(.app(AppInfo(name: app.name, icon: app.icon, path: app.path, bundleId: app.bundleId, lastOpenedDate: app.lastOpenedDate, installDate: app.installDate,  page: maxPage)))
      }
   }
   
   private func saveHiddenApps() {
      print("Save hidden apps.")
      userDefaults.set(Array(hiddenAppPaths), forKey: hiddenAppsKey)
   }
   
   func hideApp(path: String) {
      print("Hide app: \(path)")
      hiddenAppPaths.insert(path)
      loadAppGridItems(appsPerPage: settingsManager.settings.appsPerPage)
   }
   
   func unhideApp(path: String, appsPerPage: Int) {
      print("Unhide app: \(path)")
      hiddenAppPaths.remove(path)
      loadAppGridItems(appsPerPage: appsPerPage)
   }
   
   func getHiddenApps() -> [AppInfo] {
      let allApps = discoverApps()
      return allApps.filter { hiddenAppPaths.contains($0.path) }
   }
   
   private func isItemHidden(_ item: AppGridItem) -> Bool {
      switch item {
      case .app(let app):
         return hiddenAppPaths.contains(app.path)
      case .folder(_):
         return false
      case .category:
         return false
      }
   }
   
   func incrementOpenCount(forPath path: String) {
      print("Increment open count for app at path: \(path)")
      var updated = false
      
      for pageIndex in 0..<pages.count {
         for itemIndex in 0..<pages[pageIndex].count {
            let item = pages[pageIndex][itemIndex]
            
            switch item {
            case .app(let app):
               if app.path == path {
                  let updatedApp = AppInfo(
                     name: app.name,
                     icon: app.icon,
                     path: app.path,
                     bundleId: app.bundleId,
                     lastOpenedDate: app.lastOpenedDate,
                     installDate: app.installDate,
                     page: app.page,
                     openCount: app.openCount + 1
                  )
                  pages[pageIndex][itemIndex] = .app(updatedApp)
                  updated = true
                  break
               }
            case .folder(let folder):
               // Check if the app is in the folder
               if let appIndex = folder.apps.firstIndex(where: { $0.path == path }) {
                  var updatedApps = folder.apps
                  let app = updatedApps[appIndex]
                  updatedApps[appIndex] = AppInfo(
                     name: app.name,
                     icon: app.icon,
                     path: app.path,
                     bundleId: app.bundleId,
                     lastOpenedDate: app.lastOpenedDate,
                     installDate: app.installDate,
                     page: app.page,
                     openCount: app.openCount + 1
                  )
                  let updatedFolder = Folder(name: folder.name, page: folder.page, apps: updatedApps)
                  pages[pageIndex][itemIndex] = .folder(updatedFolder)
                  updated = true
                  break
               }
            case .category:
               break
            }
            
            if updated {
               break
            }
         }
         
         if updated {
            break
         }
      }
      
      if updated {
         saveAppGridItems()
      }
   }
}
