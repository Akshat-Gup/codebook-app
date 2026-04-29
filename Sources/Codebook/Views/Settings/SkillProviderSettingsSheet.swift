import SwiftUI

// MARK: - Skill Provider Settings Sheet

struct SkillProviderSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let skill: EcosystemPackage
    let targets: [ProviderInstallDestination]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose which providers have this skill installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 { Divider().padding(.horizontal, 12) }
                        let installed = model.isEcosystemPackageInstalled(skill, targetID: target.id)
                        HStack(spacing: 12) {
                            Group {
                                if let provider = target.integrationProvider {
                                    PlatformIconView(provider: provider, size: 20)
                                } else {
                                    Image(systemName: target.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                }
                            }

                            Text(target.name)
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            Toggle(isOn: Binding(
                                get: { installed },
                                set: { on in
                                    Task {
                                        if on {
                                            await model.installEcosystemPackage(skill, targetIDs: [target.id])
                                        } else {
                                            await model.uninstallEcosystemPackage(skill, targetIDs: [target.id])
                                        }
                                    }
                                }
                            )) {
                                EmptyView()
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
            }
            .padding(20)
            .frame(width: 380, alignment: .topLeading)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                            .foregroundStyle(.purple)
                        Text(skill.name)
                            .font(.title3.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
