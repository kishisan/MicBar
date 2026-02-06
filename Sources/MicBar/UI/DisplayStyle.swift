import Foundation

enum DisplayStyle: Int, CaseIterable {
    case textOnly = 0
    case iconAndText = 1
    case iconOnly = 2

    var label: String {
        switch self {
        case .textOnly: return "Text Only"
        case .iconAndText: return "Icon & Text"
        case .iconOnly: return "Icon Only"
        }
    }
}
