import SwiftUI

struct RemoveDropDelegate: DropDelegate {
   @Binding var pages: [[AppGridItem]]
   @Binding var folder: Folder
   @Binding var draggedApp: AppInfo?
   let appsPerPage: Int

   func performDrop(info: DropInfo) -> Bool {
      guard let draggedApp = draggedApp else { return false }

      if let index = folder.apps.firstIndex(where: { $0.id == draggedApp.id }) {
         withAnimation(LaunchpadConstants.dragDropAnimation) {
            let removedApp = folder.apps.remove(at: index)
            
            // Find folder location once for both operations
            if let (pageIndex, folderIndex) = findFolderLocation() {
               addAppToPage(app: removedApp, pageIndex: pageIndex)
               
               // Remove empty folder from pages
               if folder.apps.isEmpty {
                  pages[pageIndex].remove(at: folderIndex)
               }
            }
         }
      }

      AppManager.shared.saveAppGridItems()
      self.draggedApp = nil
      return true
   }
   
   private func findFolderLocation() -> (pageIndex: Int, folderIndex: Int)? {
      for (pageIndex, page) in pages.enumerated() {
         if let folderIndex = page.firstIndex(where: { $0.id == folder.id }) {
            return (pageIndex, folderIndex)
         }
      }
      return nil
   }

   private func addAppToPage(app: AppInfo, pageIndex: Int) {
      let updatedApp = AppInfo(name: app.name, icon: app.icon, path: app.path, bundleId: app.bundleId, lastOpenedDate: app.lastOpenedDate, installDate: app.installDate, page: pageIndex)
      pages[pageIndex].append(.app(updatedApp))
      PageOverflowHelper.handleOverflow(pages: &pages, pageIndex: pageIndex, appsPerPage: appsPerPage)
   }

   func dropUpdated(info: DropInfo) -> DropProposal? {
      return DropProposal(operation: .move)
   }
}
