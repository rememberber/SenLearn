import SwiftUI

struct SpeechLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    private let licenses = ["KokoroApache2", "SherpaApache2", "OnnxRuntimeMIT", "ESpeakGPL3", "PiperPhonemizeMIT", "CppJiebaMIT"]
    var body: some View {
        NavigationStack {
            List {
                Section { Text(contents("ThirdPartyNotices")).font(.footnote).textSelection(.enabled) }
                ForEach(licenses, id: \.self) { name in
                    DisclosureGroup(name) {
                        Text(contents(name)).font(.caption).textSelection(.enabled)
                    }
                }
            }.navigationTitle("开源组件与许可").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func contents(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件暂时不可用。" }
        return text
    }
}
