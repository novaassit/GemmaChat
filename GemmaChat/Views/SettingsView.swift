import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 지도 앱") {
                    Picker("지도", selection: $settings.preferredMapProvider) {
                        ForEach(MapProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text("\"지도에서 찾아줘\" 같이 앱을 지정하지 않으면 선택한 앱이 사용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
