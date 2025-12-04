import XCTest
import AppKit
@testable import LaunchpadPlus

@MainActor
final class AppManagerOpenCountTests: BaseTestCase {
   
   // MARK: - Open Count Increment Tests
   
   func testIncrementOpenCountForSingleApp() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app = AppInfo(
         name: "Test App",
         icon: mockIcon,
         path: "/Applications/TestApp.app",
         bundleId: "com.test.app",
         lastOpenedDate: nil,
         installDate: nil,
         page: 0,
         openCount: 0
      )
      
      appManager.pages = [[.app(app)]]
      
      appManager.incrementOpenCount(forPath: "/Applications/TestApp.app")
      
      let items = appManager.pages.flatMap { $0 }
      XCTAssertEqual(items.count, 1, "Should have 1 item")
      
      if case .app(let updatedApp) = items[0] {
         XCTAssertEqual(updatedApp.openCount, 1, "Open count should be incremented to 1")
      } else {
         XCTFail("Item should be an app")
      }
   }
   
   func testIncrementOpenCountMultipleTimes() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app = AppInfo(
         name: "Test App",
         icon: mockIcon,
         path: "/Applications/TestApp.app",
         bundleId: "com.test.app",
         lastOpenedDate: nil,
         installDate: nil,
         page: 0,
         openCount: 0
      )
      
      appManager.pages = [[.app(app)]]
      
      // Increment multiple times
      appManager.incrementOpenCount(forPath: "/Applications/TestApp.app")
      appManager.incrementOpenCount(forPath: "/Applications/TestApp.app")
      appManager.incrementOpenCount(forPath: "/Applications/TestApp.app")
      
      let items = appManager.pages.flatMap { $0 }
      
      if case .app(let updatedApp) = items[0] {
         XCTAssertEqual(updatedApp.openCount, 3, "Open count should be incremented to 3")
      } else {
         XCTFail("Item should be an app")
      }
   }
   
   func testIncrementOpenCountForAppInFolder() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(
         name: "App 1",
         icon: mockIcon,
         path: "/Applications/App1.app",
         bundleId: "com.test.1",
         lastOpenedDate: nil,
         installDate: nil,
         page: 0,
         openCount: 0
      )
      let app2 = AppInfo(
         name: "App 2",
         icon: mockIcon,
         path: "/Applications/App2.app",
         bundleId: "com.test.2",
         lastOpenedDate: nil,
         installDate: nil,
         page: 0,
         openCount: 0
      )
      
      let folder = Folder(name: "Test Folder", page: 0, apps: [app1, app2])
      appManager.pages = [[.folder(folder)]]
      
      appManager.incrementOpenCount(forPath: "/Applications/App1.app")
      
      let items = appManager.pages.flatMap { $0 }
      
      if case .folder(let updatedFolder) = items[0] {
         XCTAssertEqual(updatedFolder.apps[0].openCount, 1, "App in folder should have open count incremented")
         XCTAssertEqual(updatedFolder.apps[1].openCount, 0, "Other app in folder should have open count 0")
      } else {
         XCTFail("Item should be a folder")
      }
   }
   
   func testIncrementOpenCountAcrossPages() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(name: "App 1", icon: mockIcon, path: "/App1.app", bundleId: "com.test.1", lastOpenedDate: nil, installDate: nil, page: 0)
      let app2 = AppInfo(name: "App 2", icon: mockIcon, path: "/App2.app", bundleId: "com.test.2", lastOpenedDate: nil, installDate: nil, page: 1)
      let app3 = AppInfo(name: "App 3", icon: mockIcon, path: "/App3.app", bundleId: "com.test.3", lastOpenedDate: nil, installDate: nil, page: 1)
      
      appManager.pages = [[.app(app1)], [.app(app2), .app(app3)]]
      
      appManager.incrementOpenCount(forPath: "/App2.app")
      
      if case .app(let updatedApp) = appManager.pages[1][0] {
         XCTAssertEqual(updatedApp.openCount, 1, "App on second page should have open count incremented")
      } else {
         XCTFail("Item should be an app")
      }
   }
   
   // MARK: - Sort by Most Opened Tests
   
   func testSortByMostOpened() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(name: "App 1", icon: mockIcon, path: "/App1.app", bundleId: "com.test.1", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      let app2 = AppInfo(name: "App 2", icon: mockIcon, path: "/App2.app", bundleId: "com.test.2", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 10)
      let app3 = AppInfo(name: "App 3", icon: mockIcon, path: "/App3.app", bundleId: "com.test.3", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 2)
      
      appManager.pages = [[.app(app1), .app(app2), .app(app3)]]
      
      appManager.sortItems(by: .mostOpened, appsPerPage: 20)
      
      let items = appManager.pages.flatMap { $0 }
      
      // Most opened should be first
      if case .app(let firstApp) = items[0] {
         XCTAssertEqual(firstApp.name, "App 2", "App with highest open count should be first")
         XCTAssertEqual(firstApp.openCount, 10)
      } else {
         XCTFail("First item should be an app")
      }
      
      // Second most opened should be second
      if case .app(let secondApp) = items[1] {
         XCTAssertEqual(secondApp.name, "App 1", "App with second highest open count should be second")
         XCTAssertEqual(secondApp.openCount, 5)
      } else {
         XCTFail("Second item should be an app")
      }
      
      // Least opened should be last
      if case .app(let thirdApp) = items[2] {
         XCTAssertEqual(thirdApp.name, "App 3", "App with lowest open count should be last")
         XCTAssertEqual(thirdApp.openCount, 2)
      } else {
         XCTFail("Third item should be an app")
      }
   }
   
   func testSortByMostOpenedWithZeroCounts() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(name: "Zebra", icon: mockIcon, path: "/App1.app", bundleId: "com.test.1", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 0)
      let app2 = AppInfo(name: "Apple", icon: mockIcon, path: "/App2.app", bundleId: "com.test.2", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      let app3 = AppInfo(name: "Beta", icon: mockIcon, path: "/App3.app", bundleId: "com.test.3", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 0)
      
      appManager.pages = [[.app(app1), .app(app2), .app(app3)]]
      
      appManager.sortItems(by: .mostOpened, appsPerPage: 20)
      
      let items = appManager.pages.flatMap { $0 }
      
      // App with count > 0 should be first
      if case .app(let firstApp) = items[0] {
         XCTAssertEqual(firstApp.name, "Apple", "App with open count > 0 should be first")
      } else {
         XCTFail("First item should be an app")
      }
      
      // Apps with zero count should be sorted by name
      if case .app(let secondApp) = items[1] {
         XCTAssertEqual(secondApp.name, "Beta", "Apps with zero count should be sorted by name")
      } else {
         XCTFail("Second item should be an app")
      }
      
      if case .app(let thirdApp) = items[2] {
         XCTAssertEqual(thirdApp.name, "Zebra")
      } else {
         XCTFail("Third item should be an app")
      }
   }
   
   func testSortByMostOpenedWithEqualCounts() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(name: "Zebra", icon: mockIcon, path: "/App1.app", bundleId: "com.test.1", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      let app2 = AppInfo(name: "Apple", icon: mockIcon, path: "/App2.app", bundleId: "com.test.2", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      let app3 = AppInfo(name: "Beta", icon: mockIcon, path: "/App3.app", bundleId: "com.test.3", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      
      appManager.pages = [[.app(app1), .app(app2), .app(app3)]]
      
      appManager.sortItems(by: .mostOpened, appsPerPage: 20)
      
      let items = appManager.pages.flatMap { $0 }
      
      // Apps with equal count should be sorted by name
      if case .app(let firstApp) = items[0] {
         XCTAssertEqual(firstApp.name, "Apple", "Apps with equal open count should be sorted by name")
      } else {
         XCTFail("First item should be an app")
      }
      
      if case .app(let secondApp) = items[1] {
         XCTAssertEqual(secondApp.name, "Beta")
      } else {
         XCTFail("Second item should be an app")
      }
      
      if case .app(let thirdApp) = items[2] {
         XCTAssertEqual(thirdApp.name, "Zebra")
      } else {
         XCTFail("Third item should be an app")
      }
   }
   
   func testSortByMostOpenedWithFolders() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app1 = AppInfo(name: "App 1", icon: mockIcon, path: "/App1.app", bundleId: "com.test.1", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 5)
      let app2 = AppInfo(name: "App 2", icon: mockIcon, path: "/App2.app", bundleId: "com.test.2", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 3)
      let app3 = AppInfo(name: "Folder App 1", icon: mockIcon, path: "/FolderApp1.app", bundleId: "com.test.f1", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 10)
      let app4 = AppInfo(name: "Folder App 2", icon: mockIcon, path: "/FolderApp2.app", bundleId: "com.test.f2", lastOpenedDate: nil, installDate: nil, page: 0, openCount: 2)
      
      let folder = Folder(name: "Test Folder", page: 0, apps: [app3, app4])
      
      appManager.pages = [[.app(app1), .folder(folder), .app(app2)]]
      
      appManager.sortItems(by: .mostOpened, appsPerPage: 20)
      
      let items = appManager.pages.flatMap { $0 }
      
      // Folder with total count of 12 should be first
      if case .folder(let firstFolder) = items[0] {
         XCTAssertEqual(firstFolder.name, "Test Folder", "Folder with highest total open count should be first")
      } else {
         XCTFail("First item should be a folder")
      }
      
      // App with count 5 should be second
      if case .app(let secondApp) = items[1] {
         XCTAssertEqual(secondApp.name, "App 1")
      } else {
         XCTFail("Second item should be an app")
      }
   }
   
   // MARK: - Persistence Tests
   
   func testOpenCountPersistence() {
      let mockIcon = NSImage(size: NSSize(width: 64, height: 64))
      let app = AppInfo(
         name: "Test App",
         icon: mockIcon,
         path: "/Applications/TestApp.app",
         bundleId: "com.test.app",
         lastOpenedDate: nil,
         installDate: nil,
         page: 0,
         openCount: 0
      )
      
      appManager.pages = [[.app(app)]]
      
      // Increment and save
      appManager.incrementOpenCount(forPath: "/Applications/TestApp.app")
      appManager.saveAppGridItems()
      
      // Clear and reload
      appManager.pages = [[]]
      
      // Mock apps for loading
      let mockApps = [app]
      let savedData = UserDefaults.standard.array(forKey: gridItemsKey) as? [[String: Any]]
      XCTAssertNotNil(savedData, "Saved data should exist")
      
      if let savedData = savedData,
         let firstItem = savedData.first,
         let savedOpenCount = firstItem["openCount"] as? Int {
         XCTAssertEqual(savedOpenCount, 1, "Open count should be persisted")
      } else {
         XCTFail("Could not load persisted open count")
      }
   }
}
