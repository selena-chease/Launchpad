import AppKit
import SwiftUI

struct PagedGridView: View {
   @EnvironmentObject private var settingsManager: SettingsManager

   @Binding var pages: [[AppGridItem]]
   @Binding var showSettings: Bool

   @State private var currentPage = 1
   @State private var lastScrollTime = Date.distantPast
   @State private var accumulatedScrollX: CGFloat = 0
   @State private var accumulatedScrollY: CGFloat = 0
   @State private var hasChangedPageInCurrentGesture = false
   @State private var eventMonitor: Any?
   @State private var searchText = ""
   @State private var selectedSearchIndex = 0
   @State private var draggedItem: AppGridItem?
   @State private var selectedFolder: Folder?
   @State private var sortOrder: SortOrder = SortOrder.defaultLayout
   @State private var selectedCategory: Category?
   @State private var isEditMode = false
   
   // Mouse drag state
   @State private var isMouseDragging = false
   @State private var mouseDragStartX: CGFloat = 0
   @State private var mouseDragCurrentX: CGFloat = 0
   @State private var dragStartPage = 0

   private var totalPages: Int {
      return pages.count + 1  // +1 for category page
   }

   var body: some View {
      VStack(spacing: 0) {
         SearchBarView(
            searchText: $searchText,
            sortOrder: $sortOrder,
            onSortChange: handleSort,
            onSettingsOpen: { showSettings = true },
            transparency: settingsManager.settings.transparency,
            showIcons: settingsManager.settings.showIconsInSearch
         )

         GeometryReader { geo in
            if searchText.isEmpty {
               HStack(spacing: 0) {
                  // Category page
                  CategoryPageView(
                     allApps: allApps(),
                     settings: settingsManager.settings,
                     onItemTap: handleTap
                  )
                  .frame(width: geo.size.width, height: geo.size.height)

                  // Regular app pages
                  ForEach(pages.indices, id: \.self) { pageIndex in
                     SinglePageView(
                        pages: $pages,
                        draggedItem: $draggedItem,
                        isEditMode: $isEditMode,
                        canEdit: sortOrder == .defaultLayout,
                        pageIndex: pageIndex,
                        settings: settingsManager.settings,
                        isFolderOpen: selectedFolder != nil,
                        onItemTap: handleTap
                     )
                     .frame(width: geo.size.width, height: geo.size.height)
                  }
               }
               .offset(x: calculatePageOffset(width: geo.size.width))
               .animation(isMouseDragging ? nil : LaunchpadConstants.springAnimation, value: currentPage)
               .padding(.bottom, 16)
            } else {
               SearchResultsView(
                  apps: filteredApps(),
                  settings: settingsManager.settings,
                  selectedIndex: selectedSearchIndex,
                  onItemTap: handleTap
               )
               .frame(width: geo.size.width, height: geo.size.height)
            }
         }
         PageIndicatorView(
            currentPage: $currentPage,
            pageCount: totalPages,
            isFolderOpen: selectedFolder != nil,
            searchText: searchText,
            settings: settingsManager.settings
         )
      }
      .onAppear(perform: setupEventMonitoring)
      .onDisappear(perform: cleanupEventMonitoring)
      .onChange(of: searchText) {
         selectedSearchIndex = 0
      }

      FolderDetailView(
         pages: $pages,
         folder: $selectedFolder,
         settings: settingsManager.settings,
         onItemTap: handleTap
      )

      CategoryDetailView(
         category: $selectedCategory,
         allApps: allApps(),
         settings: settingsManager.settings,
         onItemTap: handleTap
      )

      PageDropZonesView(
         currentPage: currentPage,
         totalPages: totalPages,
         draggedItem: draggedItem,
         onNavigateLeft: navigateToPreviousPage,
         onNavigateRight: { navigateToNextPage(allowCreatePage: true) },
         transparency: settingsManager.settings.transparency
      )
   }
   
   private func calculatePageOffset(width: CGFloat) -> CGFloat {
      let baseOffset = -CGFloat(currentPage) * width
      
      // Add drag offset if actively dragging
      if isMouseDragging {
         let dragOffset = mouseDragCurrentX - mouseDragStartX
         return baseOffset + dragOffset
      }
      
      return baseOffset
   }

   private func filteredApps() -> [AppInfo] {
      guard !searchText.isEmpty else { return [] }

      let searchTerm = searchText.lowercased()
      return pages.flatMap { $0 }.flatMap { item -> [AppInfo] in
         switch item {
         case .app(let app):
            return app.name.lowercased().contains(searchTerm) ? [app] : []
         case .folder(let folder):
            if folder.name.lowercased().contains(searchTerm) {
               return folder.apps
            } else {
               return folder.apps.filter { $0.name.lowercased().contains(searchTerm) }
            }
         case .category:
            return []
         }
      }
   }

   private func allApps() -> [AppInfo] {
      pages.flatMap { $0 }.compactMap { item in
         if case .app(let app) = item {
            return app
         }
         return nil
      }
   }

   private func handleTap(item: AppGridItem) {
      switch item {
      case .app(let app):
         AppLauncher.launch(path: app.path)
      case .folder(let folder):
         selectedFolder = folder
      case .category(let category):
         selectedCategory = category
      }
   }

   private func setupEventMonitoring() {
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
         switch event.type {
         case .scrollWheel:
            return handleScrollEvent(event: event)
         case .keyDown:
            return handleKeyEvent(event: event)
         case .flagsChanged:
            return handleFlagsChanged(event: event)
         case .leftMouseDown:
            return handleMouseDown(event: event)
         case .leftMouseDragged:
            return handleMouseDragged(event: event)
         case .leftMouseUp:
            return handleMouseUp(event: event)
         default:
            return event
         }
      }

      NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
         guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

         Task { @MainActor in
            if activatedApp.bundleIdentifier == Bundle.main.bundleIdentifier {
               handleAppActivation()
            } else {
               AppLauncher.exit()
            }
         }
      }
   }

   private func cleanupEventMonitoring() {
      if let monitor = eventMonitor {
         NSEvent.removeMonitor(monitor)
         eventMonitor = nil
      }
   }

   private func handleScrollEvent(event: NSEvent) -> NSEvent? {
      guard searchText.isEmpty && selectedFolder == nil && selectedCategory == nil && showSettings == false else { return event }

      let absX = abs(event.scrollingDeltaX)
      let absY = abs(event.scrollingDeltaY)

      // Support both horizontal (trackpad) and vertical (mouse wheel) scrolling
      guard (absX > 0 || absY > 0) else { return event }

      let now = Date()
      let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
      
      // Detect new gesture: reset accumulation if enough time passed, but keep the page change flag longer
      if timeSinceLastScroll > 0.3 {
         accumulatedScrollX = 0
         accumulatedScrollY = 0
      }
      
      // Only reset the page change flag after a longer pause (gesture truly ended)
      if event.phase == .began || event.phase == .ended || event.phase == .cancelled || timeSinceLastScroll > 0.8 {
         hasChangedPageInCurrentGesture = false
      }
      
      // If we already changed page in this gesture, ignore further scrolling
      guard !hasChangedPageInCurrentGesture else { return event }
      
      // Update last scroll time
      lastScrollTime = now
      
      // Determine which direction has more movement and accumulate accordingly
      if absX >= absY {
         // Horizontal scroll (trackpad swipe)
         accumulatedScrollY = 0
         accumulatedScrollX += event.scrollingDeltaX

         if accumulatedScrollX <= -settingsManager.settings.scrollActivationThreshold {
            currentPage = min(currentPage + 1, totalPages - 1)
            hasChangedPageInCurrentGesture = true
            accumulatedScrollX = 0
            return nil
         } else if accumulatedScrollX >= settingsManager.settings.scrollActivationThreshold {
            currentPage = max(currentPage - 1, 0)
            hasChangedPageInCurrentGesture = true
            accumulatedScrollX = 0
            return nil
         }
      } else {
         // Vertical scroll (mouse wheel) - disabled on category page
         guard currentPage != 0 else { return event }

         accumulatedScrollX = 0
         accumulatedScrollY += event.scrollingDeltaY

         if accumulatedScrollY <= -settingsManager.settings.scrollActivationThreshold {
            currentPage = min(currentPage + 1, totalPages - 1)
            hasChangedPageInCurrentGesture = true
            accumulatedScrollY = 0
            return nil
         } else if accumulatedScrollY >= settingsManager.settings.scrollActivationThreshold {
            currentPage = max(currentPage - 1, 0)
            hasChangedPageInCurrentGesture = true
            accumulatedScrollY = 0
            return nil
         }
      }

      return event
   }

   private func handleMouseDown(event: NSEvent) -> NSEvent? {
      guard searchText.isEmpty && selectedFolder == nil && selectedCategory == nil && showSettings == false else { return event }
      
      // Only initiate drag if not clicking on an app item (allow normal drag-and-drop)
      guard draggedItem == nil else { return event }
      
      // Store the initial mouse position
      mouseDragStartX = event.locationInWindow.x
      mouseDragCurrentX = mouseDragStartX
      dragStartPage = currentPage
      isMouseDragging = false  // Don't set to true yet, wait for actual drag
      
      return event
   }
   
   private func handleMouseDragged(event: NSEvent) -> NSEvent? {
      guard searchText.isEmpty && selectedFolder == nil && selectedCategory == nil && showSettings == false else { return event }
      
      // Only handle page dragging if not dragging an app item
      guard draggedItem == nil else { return event }
      
      // Update current drag position
      mouseDragCurrentX = event.locationInWindow.x
      let dragDistance = mouseDragCurrentX - mouseDragStartX
      
      // Consider it a drag gesture if moved more than a threshold (e.g., 10 pixels)
      if !isMouseDragging && abs(dragDistance) > 10 {
         isMouseDragging = true
      }
      
      // If we're in a drag gesture, prevent default behavior
      if isMouseDragging {
         return nil
      }
      
      return event
   }
   
   private func handleMouseUp(event: NSEvent) -> NSEvent? {
      guard searchText.isEmpty && selectedFolder == nil && selectedCategory == nil && showSettings == false else { 
         isMouseDragging = false
         return event 
      }
      
      // Only handle if we were in a drag gesture
      guard isMouseDragging else { return event }
      
      let dragDistance = mouseDragCurrentX - mouseDragStartX
      let threshold: CGFloat = 100  // Minimum drag distance to trigger page change
      
      // Determine if we should change pages based on drag distance
      if dragDistance < -threshold {
         // Dragged left, go to next page
         withAnimation(LaunchpadConstants.springAnimation) {
            currentPage = min(currentPage + 1, totalPages - 1)
         }
      } else if dragDistance > threshold {
         // Dragged right, go to previous page
         withAnimation(LaunchpadConstants.springAnimation) {
            currentPage = max(currentPage - 1, 0)
         }
      } else {
         // Drag was too short, snap back to original page
         withAnimation(LaunchpadConstants.springAnimation) {
            currentPage = dragStartPage
         }
      }
      
      // Reset drag state
      isMouseDragging = false
      mouseDragStartX = 0
      mouseDragCurrentX = 0
      
      return nil
   }

   private func handleFlagsChanged(event: NSEvent) -> NSEvent? {
      // Check if Alt/Option key is pressed
      let altKeyPressed = event.modifierFlags.contains(.option)

      if altKeyPressed != isEditMode {
         withAnimation(LaunchpadConstants.fadeAnimation) {
            isEditMode = altKeyPressed
         }
      }

      return event
   }

   private func handleKeyEvent(event: NSEvent) -> NSEvent? {
      // Handle special keys
      switch event.keyCode {
      case KeyCodeConstants.escape:
         if !searchText.isEmpty {
            searchText = ""
            selectedSearchIndex = 0
         } else if selectedFolder == nil && selectedCategory == nil {
            AppLauncher.exit()
         } else {
            selectedFolder = nil
            selectedCategory = nil
         }
      case KeyCodeConstants.leftArrow:
         if !searchText.isEmpty {
            navigateSearchLeft()
            return nil
         } else if selectedFolder == nil && selectedCategory == nil {
            navigateToPreviousPage()
         }
      case KeyCodeConstants.rightArrow:
         if !searchText.isEmpty {
            navigateSearchRight()
            return nil
         } else if selectedFolder == nil && selectedCategory == nil {
            navigateToNextPage()
         }
      case KeyCodeConstants.downArrow:
         if !searchText.isEmpty {
            navigateSearchDown()
            return nil
         }
      case KeyCodeConstants.upArrow:
         if !searchText.isEmpty {
            navigateSearchUp()
            return nil
         }
      case KeyCodeConstants.comma:
         if event.modifierFlags.contains(.command) {
            showSettings = true
         }
      case KeyCodeConstants.r:
         if event.modifierFlags.contains(.command) {
            AppManager.shared.refreshApps(appsPerPage: settingsManager.settings.appsPerPage)
         }
      case KeyCodeConstants.enter:
         if selectedCategory != nil {
            launchAllAppsInCategory()
         } else {
            launchSelectedSearchResult()
         }
      default:
         break
      }

      return event
   }

   private func navigateToPreviousPage() {
      guard currentPage > 0 else { return }

      withAnimation(LaunchpadConstants.springAnimation) {
         currentPage = currentPage - 1
      }
   }

   private func navigateToNextPage(allowCreatePage: Bool = false) {
      if currentPage < totalPages - 1 {
         withAnimation(LaunchpadConstants.springAnimation) {
            currentPage += 1
         }
      } else if allowCreatePage {
         createNewPage()
      }
   }

   private func createNewPage() {
      pages.append([])
      withAnimation(LaunchpadConstants.springAnimation) {
         currentPage = totalPages - 1
      }
   }

   private func launchSelectedSearchResult() {
      guard !searchText.isEmpty else { return }
      let apps = filteredApps()
      guard selectedSearchIndex >= 0 && selectedSearchIndex < apps.count else { return }

      AppLauncher.launch(path: apps[selectedSearchIndex].path)
   }

   private func launchAllAppsInCategory() {
      guard selectedCategory != nil else { return }
      let categoryApps = CategoryManager.shared.getAppsForCategory(category: selectedCategory!, from: allApps())
      for app in categoryApps {
         AppLauncher.launch(path: app.path)
      }
   }

   private func handleSort(sortOrder: SortOrder) {
      AppManager.shared.sortItems(by: sortOrder, appsPerPage: settingsManager.settings.appsPerPage)
   }

   private func navigateSearchLeft() {
      let apps = filteredApps()
      guard !apps.isEmpty else { return }

      selectedSearchIndex = NavigationHelper.navigateLeft(currentIndex: selectedSearchIndex, itemCount: apps.count)
   }

   private func navigateSearchRight() {
      let apps = filteredApps()
      guard !apps.isEmpty else { return }

      selectedSearchIndex = NavigationHelper.navigateRight(currentIndex: selectedSearchIndex, itemCount: apps.count)
   }

   private func navigateSearchUp() {
      let apps = filteredApps()
      guard !apps.isEmpty else { return }

      selectedSearchIndex = NavigationHelper.navigateUp(currentIndex: selectedSearchIndex, itemCount: apps.count, columns: settingsManager.settings.columns)
   }
   
   private func navigateSearchDown() {
      let apps = filteredApps()
      guard !apps.isEmpty else { return }

      selectedSearchIndex = NavigationHelper.navigateDown(currentIndex: selectedSearchIndex, itemCount: apps.count, columns: settingsManager.settings.columns)
   }

   private func handleAppActivation() {
      if settingsManager.settings.resetOnRelaunch {
         currentPage = 1
         selectedFolder = nil
         selectedCategory = nil
         searchText = ""
      }

      if !SettingsManager.shared.settings.isActivated {
         showSettings = true
      }
   }
}
