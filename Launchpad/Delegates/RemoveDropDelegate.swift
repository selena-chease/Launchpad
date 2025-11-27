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
            addAppToPage(app: removedApp)
            
            // Remove empty folder from pages
            if folder.apps.isEmpty {
               removeEmptyFolder()
            }
         }
      }

      AppManager.shared.saveAppGridItems()
      self.draggedApp = nil
      return true
   }
   
   private func removeEmptyFolder() {
      guard let pageIndex = pages.firstIndex(where: { page in page.contains(where: { $0.id == folder.id }) }),
            let folderIndex = pages[pageIndex].firstIndex(where: { $0.id == folder.id }) else { return }
      pages[pageIndex].remove(at: folderIndex)
   }

   private func addAppToPage(app: AppInfo) {
      guard let pageIndex = pages.firstIndex(where: { page in page.contains(where: { $0.id == folder.id }) }) else { return }
      let updatedApp = AppInfo(name: app.name, icon: app.icon, path: app.path, bundleId: app.bundleId, lastOpenedDate: app.lastOpenedDate, installDate: app.installDate, page: pageIndex)
      pages[pageIndex].append(.app(updatedApp))
      PageOverflowHelper.handleOverflow(pages: &pages, pageIndex: pageIndex, appsPerPage: appsPerPage)
   }

   func dropUpdated(info: DropInfo) -> DropProposal? {
      return DropProposal(operation: .move)
   }
}
