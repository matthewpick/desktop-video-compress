import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Watching") {
                    HStack {
                        Text(preferences.watchedFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Button("Change…") { model.chooseWatchedFolder() }
                    }
                }

                Toggle("Compress files already in the folder at launch", isOn: $preferences.compressExistingOnLaunch)
            } footer: {
                Text("Only .mp4, .m4v, and .mov files are compressed. Other formats are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Compression") {
                Picker("Quality", selection: $preferences.qualityTier) {
                    ForEach(QualityTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }

                Picker("Maximum size", selection: $preferences.maxDimension) {
                    ForEach(MaxDimension.allCases) { dimension in
                        Text(dimension.displayName).tag(dimension)
                    }
                }

                Toggle("Move the original to the Trash", isOn: $preferences.trashOriginal)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))

                Toggle("Show notifications", isOn: $preferences.notificationsEnabled)
            }

            Section {
                LabeledContent("Version", value: AppInfo.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
