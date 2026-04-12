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

enum LLMMode: String, CaseIterable, Identifiable {
    case local = "local"
    case remote = "remote"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "로컬 모델 (On-Device)"
        case .remote: return "외부 API"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var preferredMapProvider: MapProvider {
        didSet { UserDefaults.standard.set(preferredMapProvider.rawValue, forKey: "preferredMapApp") }
    }

    @Published var llmMode: LLMMode {
        didSet { UserDefaults.standard.set(llmMode.rawValue, forKey: "llmMode") }
    }

    @Published var remoteHost: String {
        didSet { UserDefaults.standard.set(remoteHost, forKey: "remoteHost") }
    }

    @Published var remotePort: String {
        didSet { UserDefaults.standard.set(remotePort, forKey: "remotePort") }
    }

    @Published var remotePath: String {
        didSet { UserDefaults.standard.set(remotePath, forKey: "remotePath") }
    }

    @Published var remoteAPIKey: String {
        didSet { UserDefaults.standard.set(remoteAPIKey, forKey: "remoteAPIKey") }
    }

    @Published var remoteModelName: String {
        didSet { UserDefaults.standard.set(remoteModelName, forKey: "remoteModelName") }
    }

    var remoteEndpoint: String { resolvedEndpoint }

    var resolvedEndpoint: String {
        if remotePath.hasPrefix("https://") || remotePath.hasPrefix("http://") {
            return remotePath
        }
        let host = remoteHost.isEmpty ? "localhost" : remoteHost
        let port = remotePort.isEmpty ? "" : ":\(remotePort)"
        let path = remotePath.isEmpty ? "/v1/chat/completions" : remotePath
        return "http://\(host)\(port)\(path)"
    }

    private init() {
        let mapRaw = UserDefaults.standard.string(forKey: "preferredMapApp") ?? "naver"
        self.preferredMapProvider = MapProvider(rawValue: mapRaw) ?? .naver

        let modeRaw = UserDefaults.standard.string(forKey: "llmMode") ?? "local"
        self.llmMode = LLMMode(rawValue: modeRaw) ?? .local

        self.remoteHost = UserDefaults.standard.string(forKey: "remoteHost") ?? ""
        self.remotePort = UserDefaults.standard.string(forKey: "remotePort") ?? "11434"
        self.remotePath = UserDefaults.standard.string(forKey: "remotePath") ?? "/v1/chat/completions"
        self.remoteAPIKey = UserDefaults.standard.string(forKey: "remoteAPIKey") ?? ""
        self.remoteModelName = UserDefaults.standard.string(forKey: "remoteModelName") ?? ""
    }
}
