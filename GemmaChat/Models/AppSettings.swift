import Foundation

enum MapProvider: String, CaseIterable, Identifiable {
    case apple = "apple"
    case naver = "naver"
    case tmap = "tmap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple 지도"
        case .naver: return "네이버 지도"
        case .tmap: return "T맵"
        }
    }

    var urlScheme: String {
        switch self {
        case .apple: return "maps"
        case .naver: return "nmap"
        case .tmap: return "tmap"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var preferredMapProvider: MapProvider {
        didSet { UserDefaults.standard.set(preferredMapProvider.rawValue, forKey: "preferredMapApp") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "preferredMapApp") ?? "naver"
        self.preferredMapProvider = MapProvider(rawValue: raw) ?? .naver
    }
}
