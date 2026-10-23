import SwiftUI

struct HelpView: View {
    @Environment(DashboardModel.self) private var dashboard

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        PageScaffold(.help) {
            VStack(alignment: .leading, spacing: 40) {
                SettingsGroup("Getting started") {
                    step(1, "Hold fn and speak", "Release to transcribe. The text is copied to your clipboard, ready to paste.")
                    step(2, "Create a style", "Styles rewrite what you said, like turning a ramble into an email.", link: ("Open Styles", .styles))
                    step(3, "Connect a provider", "Styles need an AI provider. Transcription itself never leaves your Mac.", link: ("Open Providers", .providers))
                }

                SettingsGroup("Keyboard shortcuts") {
                    shortcut("Record while held", keys: ["fn"], note: "hold", isFirst: true)
                    shortcut("Cancel recording", keys: ["esc"])
                    shortcut("Open the dashboard from the menu bar", keys: ["⌘", "D"])
                    shortcut("Quit Shh..", keys: ["⌘", "Q"])
                }

                SettingsGroup("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shh.. turns speech into text on your Mac with on-device models like Whisper, and can rewrite it with an AI style before you paste.")
                            .font(.inter(14))
                            .lineSpacing(4)
                            .foregroundStyle(Graphite.text2)
                            .frame(maxWidth: 520, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Version \(version)")
                            .font(.inter(12.5))
                            .foregroundStyle(Graphite.text3)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ description: String, link: (String, DashboardPage)? = nil) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.inter(12.5))
                .monospacedDigit()
                .foregroundStyle(Graphite.text3)
                .frame(width: 14, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.inter(14.5)).foregroundStyle(Graphite.text)
                Text(description)
                    .font(.inter(14))
                    .lineSpacing(4)
                    .foregroundStyle(Graphite.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let link {
                TextLink(link.0) { dashboard.page = link.1 }
                    .font(.inter(12.5))
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            if number > 1 {
                Rectangle().fill(Graphite.hairline).frame(height: 1)
            }
        }
    }

    private func shortcut(_ label: String, keys: [String], note: String? = nil, isFirst: Bool = false) -> some View {
        SettingRow(label, isFirst: isFirst) {
            HStack(spacing: 4) {
                if let note {
                    Text(note)
                        .font(.inter(12.5))
                        .foregroundStyle(Graphite.text3)
                        .padding(.trailing, 4)
                }
                ForEach(keys, id: \.self) { Kbd($0) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
