import Foundation

enum SortOrder: String, Codable, CaseIterable {
   case defaultLayout = "default"
   case name = "name"
   case itemType = "type"
   case lastOpened = "lastOpened"
   case installDate = "installDate"
   case mostOpened = "mostOpened"
   
   var displayName: String {
      switch self {
      case .defaultLayout:
         return L10n.sortByDefault
      case .name:
         return L10n.sortByName
      case .itemType:
         return L10n.sortByType
      case .lastOpened:
         return L10n.sortByLastOpened
      case .installDate:
         return L10n.sortByInstallDate
      case .mostOpened:
         return L10n.sortByMostOpened
      }
   }
}
