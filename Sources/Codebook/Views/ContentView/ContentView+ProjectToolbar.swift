import Charts
import SwiftUI

extension ContentView {

    // MARK: - Project toolbar (Skills, Automations, Agents.md, Activity, Diagram)

    var projectToolbar: some View {
        HStack(spacing: 6) {
            projectToolbarButton(title: "Skills", systemImage: "sparkles") {
                showProjectSkillsPopover.toggle()
            }
            .popover(isPresented: $showProjectSkillsPopover, arrowEdge: .bottom) {
                projectSkillsPopoverContent
            }

            projectToolbarButton(title: "Automations", systemImage: "square.stack.3d.up") {
                showAutomationsSheet = true
            }

            projectToolbarButton(title: "Agents.md", systemImage: "doc.text") {
                showAgentsMDSheet = true
            }

            projectToolbarButton(title: "Activity", systemImage: "chart.bar") {
                showProjectActivitySheet = true
            }

            projectToolbarButton(title: "Diagrams", systemImage: "rectangle.3.group.bubble") {
                showDiagramSheet = true
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .sheet(isPresented: $showAutomationsSheet) {
            automationsPopupSheet
                .environmentObject(model)
                .frame(width: 560, height: 480)
        }
        .sheet(isPresented: $showAgentsMDSheet) {
            agentsMDPopupSheet
                .environmentObject(model)
                .frame(width: 820, height: 580)
        }
        .sheet(isPresented: $showProjectActivitySheet) {
            projectActivityPopupSheet
                .environmentObject(model)
                .frame(width: 740, height: 700)
        }
        .sheet(isPresented: $showDiagramSheet) {
            DiagramSheet()
                .environmentObject(model)
                .frame(width: 900, height: 700)
        }
    }

    func projectToolbarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(AppControlChrome.charcoal)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                AppControlChrome.glassShareButtonBackground(cornerRadius: 10)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project Skills popover

    @ViewBuilder
    func skillRow(skill: EcosystemPackage, targets: [ProviderInstallDestination]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
                .frame(width: 16)

            Text(skill.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()

            Button {
                showProjectSkillsPopover = false
                skillSettingsTarget = skill
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
                    }
            }
            .buttonStyle(.plain)
            .help("Manage providers")

            Button {
                let globalTargets = Set(targets.map(\.id))
                Task {
                    await model.uninstallEcosystemPackage(skill, targetIDs: globalTargets)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
                    }
            }
            .buttonStyle(.plain)
            .help("Remove skill")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    func availableSkillRow(skill: EcosystemPackage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(skill.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button {
                let targetIDs = Set(model.ecosystemGlobalInstallTargets.map(\.id))
                Task { await model.installEcosystemPackage(skill, targetIDs: targetIDs) }
            } label: {
                Text("Install")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Install \(skill.name)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    var projectSkillsPopoverContent: some View {
        let installed = model.ecosystemDiscoveredInstalledPackages
            .filter { $0.kind == .skill }
        let catalogSkills = model.ecosystemCatalog.filter { $0.kind == .skill }
        let notInstalled = catalogSkills.filter { cat in
            !installed.contains(where: { Slug.make(from: $0.name) == Slug.make(from: cat.name) })
        }
        let targets = model.ecosystemGlobalInstallTargets

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skills")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(installed.count) installed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if installed.isEmpty && notInstalled.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.quaternary)
                    Text("No skills installed yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(installed.enumerated()), id: \.element.id) { index, skill in
                            if index > 0 { Divider().padding(.leading, 30) }
                            skillRow(skill: skill, targets: targets)
                        }
                        if !installed.isEmpty && !notInstalled.isEmpty {
                            Divider().padding(.vertical, 4)
                            HStack {
                                Text("Available")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                        }
                        ForEach(Array(notInstalled.enumerated()), id: \.element.id) { index, skill in
                            if index > 0 { Divider().padding(.leading, 30) }
                            availableSkillRow(skill: skill)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            Button {
                showProjectSkillsPopover = false
                withAnimation(CodebookMotion.pane) {
                    model.selectEcosystem()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("Add Skill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Automations popup sheet

    var automationsPopupSheet: some View {
        let project = model.selectedProjectSummary
        let status = project.flatMap { model.repoAutomationStatus(for: $0) }
        let promptsReady = status?.promptStoreExists == true
        let hookInstalled = promptsReady && status?.hookInstalled == true
        let configuredExportMode = project.flatMap { model.repoAutomationSettings(for: $0)?.exportMode } ?? .commit

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                CardSectionIcon(systemName: "bolt.fill", size: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automations")
                        .font(.title3.weight(.semibold))
                    Text("Export and sync your AI prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showAutomationsSheet = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let project {
                        // ── Prompts Folder card ──
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Prompts Folder")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Export prompts to a `.prompts/` folder in your repo.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if promptsReady {
                                HStack(spacing: 10) {
                                    Text("Current layout")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)

                                    Label(configuredExportMode.title, systemImage: configuredExportMode.systemImage)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Menu {
                                        ForEach(RepoAutomationExportMode.allCases, id: \.self) { mode in
                                            Button {
                                                automationExportMode = mode
                                                Task {
                                                    await model.reorganizePromptStore(for: project, mode: mode)
                                                    refreshAutomationProjectStatus()
                                                }
                                            } label: {
                                                Label(mode.title, systemImage: mode == configuredExportMode ? "checkmark" : mode.systemImage)
                                            }
                                        }
                                    } label: {
                                        Text("Reorganize")
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppControlChrome.charcoal)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background {
                                        AppControlChrome.glassShareButtonBackground(cornerRadius: 8)
                                    }
                                }

                                HStack(spacing: 10) {
                                    Button("Open prompts/") {
                                        model.openPromptStore(for: project)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    Button("Sync Now") {
                                        Task {
                                            automationProjectID = project.id
                                            await model.exportPrompts(for: project)
                                            refreshAutomationProjectStatus()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppControlChrome.charcoal)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background {
                                        AppControlChrome.glassShareButtonBackground(cornerRadius: 8)
                                    }

                                    Spacer()

                                    Button("Delete prompts/") {
                                        promptStoreConfirmation = PromptStoreConfirmationRequest(project: project, action: .deleteFolder)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.red.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.red.opacity(0.18), lineWidth: 0.5)
                                    )

                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.green)
                                        Text("Active")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        if let count = status?.promptCount {
                                            Text("· \(count) files")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            } else {
                                Button("Create .prompts/") {
                                    showCreatePromptsSetup = true
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(16)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
                        .sheet(isPresented: $showCreatePromptsSetup) {
                            automationsCreatePromptsSheet(for: project)
                        }

                        // ── Git Hook card ──
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Git Hook")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Auto-sync prompts on every commit.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 10) {
                                if hookInstalled {
                                    Button("Turn Off") {
                                        Task {
                                            await model.uninstallRepoAutomation(for: project)
                                            refreshAutomationProjectStatus()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.red.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.red.opacity(0.18), lineWidth: 0.5)
                                    )
                                } else {
                                    Button("Install Hook") {
                                        Task {
                                            _ = try? model.createPromptStore(for: project)
                                            await model.installRepoAutomationHooks(for: project)
                                            await model.exportPrompts(for: project)
                                            refreshAutomationProjectStatus()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }

                                Spacer()

                                if hookInstalled {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 7, height: 7)
                                        Text("Installed")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.quaternary)
                            Text("Select a project to configure automations.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(20)
            }
        }
    }

    func automationsCreatePromptsSheet(for project: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create .prompts/ folder")
                    .font(.headline)
                Text("Choose how to organize your exported prompts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(RepoAutomationExportMode.allCases, id: \.self) { mode in
                    Button {
                        automationExportMode = mode
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 22)
                                .foregroundStyle(automationExportMode == mode ? Color.accentColor : .secondary)
                            Text(mode.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if automationExportMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(automationExportMode == mode ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            automationExportMode == mode ? Color.accentColor.opacity(0.25) : Color(nsColor: .separatorColor).opacity(0.5),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Cancel") {
                    showCreatePromptsSetup = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))

                Spacer()

                Button("Create") {
                    showCreatePromptsSetup = false
                    Task {
                        model.setRepoAutomationExportMode(automationExportMode, for: project)
                        _ = try? model.createPromptStore(for: project)
                        refreshAutomationProjectStatus()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 340)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Agents.md popup sheet

    var agentsMDPopupSheet: some View {
        let project = model.selectedProjectSummary
        let fileContent: String = {
            guard let path = project?.path else { return "" }
            let url = URL(fileURLWithPath: path).appendingPathComponent(agentsFileTab.fileName)
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }()
        let hasFile = !fileContent.isEmpty
        let audit = model.agentsProjectAudits.first { $0.projectID == project?.id }

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Glassy toggle for AGENTS.md / CLAUDE.md
                HStack(spacing: 0) {
                    ForEach(AgentsFileTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                agentsFileTab = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(agentsFileTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(agentsFileTab == tab ? Color(nsColor: .controlBackgroundColor) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )

                if let project {
                    let synced = audit?.filesAreSynchronized == true
                    let bothExist = audit?.fileExists == true && audit?.claudeFileExists == true
                    Button {
                        Task { await model.syncInstructionFiles(for: project) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: synced && bothExist ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text(synced && bothExist ? "Synced" : "Sync")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(synced && bothExist ? AnyShapeStyle(.green) : AnyShapeStyle(Color.accentColor))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            AppControlChrome.glassShareButtonBackground(cornerRadius: 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(synced && bothExist)
                    .help(audit?.syncDetailText ?? "Merge AGENTS.md and CLAUDE.md so they contain the union of both.")
                }

                Spacer()

                Button("Done") { showAgentsMDSheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // 2-pane layout: controls left, file preview right
            HStack(alignment: .top, spacing: 0) {
                // Left pane: controls
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Suggested addons
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Addons")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 0) {
                                ForEach(Array(AgentsAdvicePack.allCases.enumerated()), id: \.offset) { index, pack in
                                    if index > 0 { Divider().padding(.leading, 28) }
                                    HStack(spacing: 8) {
                                        Toggle(isOn: Binding(
                                            get: { model.selectedAgentsAdvice.contains(pack) },
                                            set: { on in model.setAgentsAdvicePack(pack, enabled: on) }
                                        )) {
                                            EmptyView()
                                        }
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)
                                        .labelsHidden()

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(pack.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Text(pack.body.components(separatedBy: "\n").first ?? "")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
                        }

                        // AI Analysis
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Analysis")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            if let result = agentsAIAnalysisResult {
                                if result.hasPrefix("AI analysis request failed") || result.hasPrefix("Failed to get AI") || result.hasPrefix("The AI returned") {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(result)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    Text(LocalizedStringKey(result))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }

                        // Action buttons
                        if let project {
                            HStack(spacing: 8) {
                                Button("Apply") {
                                    Task { await model.applyAgentsTemplate(to: project) }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                Button {
                                    model.openInstructionFile(named: agentsFileTab.fileName, for: project)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Open")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(AppControlChrome.charcoal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        AppControlChrome.glassShareButtonBackground(cornerRadius: 7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Open \(agentsFileTab.fileName) in Finder")

                                Button {
                                    let preview = fileContent.isEmpty
                                        ? model.instructionPreview(for: project, fileName: agentsFileTab.fileName)
                                        : fileContent
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(preview, forType: .string)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Copy")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(AppControlChrome.charcoal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        AppControlChrome.glassShareButtonBackground(cornerRadius: 7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Copy \(agentsFileTab.fileName) content to clipboard")

                                Button {
                                    runAgentsMDAnalysis()
                                } label: {
                                    HStack(spacing: 4) {
                                        if agentsAIAnalysisRunning {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        Text("Analyze")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(model.insightsAIAvailable ? AnyShapeStyle(AppControlChrome.charcoal) : AnyShapeStyle(.tertiary))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        AppControlChrome.glassShareButtonBackground(cornerRadius: 7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(agentsAIAnalysisRunning || !model.insightsAIAvailable)
                                .help(model.insightsAIAvailable ? "Analyze \(agentsFileTab.fileName) for improvements" : model.insightsAvailabilityHelpText)

                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 300, idealWidth: 340)

                // Divider between panes
                Divider()

                // Right pane: scrollable file content
                ScrollView {
                    if hasFile {
                        Text(fileContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.quaternary)
                            Text("No \(agentsFileTab.fileName) found")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(agentsFileTab == .agentsMD ? "Use Apply to create one." : "Use Sync to create one.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    func runAgentsMDAnalysis() {
        guard let project = model.selectedProjectSummary,
              let path = project.path else { return }
        let fileName = agentsFileTab.fileName
        let url = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? model.instructionPreview(for: project, fileName: fileName)
        guard !content.isEmpty else { return }
        agentsAIAnalysisRunning = true
        agentsAIAnalysisResult = nil
        Task {
            let result = await model.analyzeAgentsMD(content: content, fileName: fileName)
            agentsAIAnalysisResult = result
            agentsAIAnalysisRunning = false
        }
    }

    // MARK: - Project Activity popup sheet

    var projectActivityPopupSheet: some View {
        let project = model.selectedProjectSummary
        let projectPrompts = model.importedPrompts.filter { prompt in
            guard let project else { return false }
            return prompt.projectKey == project.id
        }
        let grouped = Dictionary(grouping: projectPrompts) { prompt in
            Calendar.current.startOfDay(for: prompt.capturedAt)
        }
        .map { (date: $0.key, count: $0.value.count) }
        .sorted { $0.date > $1.date }

        let barStats: [DailyPromptStat] = grouped.reversed().map {
            DailyPromptStat(id: $0.date, day: $0.date, count: $0.count, commits: [])
        }
        let heatmapStats: [DailyPromptStat] = {
            guard let earliest = barStats.first?.day else { return [] }
            let cal = Calendar.current
            let start = cal.startOfDay(for: earliest)
            let end = cal.startOfDay(for: barStats.last?.day ?? Date())
            var stats: [DailyPromptStat] = []
            var current = start
            let byDay = Dictionary(grouping: barStats) { $0.day }.mapValues { $0.first! }
            while current <= end {
                stats.append(byDay[current] ?? DailyPromptStat(id: current, day: current, count: 0, commits: []))
                current = cal.date(byAdding: .day, value: 1, to: current) ?? end.addingTimeInterval(1)
            }
            return stats
        }()
        let barsMaxY = max(barStats.map(\.count).max() ?? 0, 1)
        let visibleDayCount = 70
        let projectActivityHeatmapGridHeight: CGFloat = 500
        let maxActivityOffset = max(0, heatmapStats.count - visibleDayCount)
        let activityOff = min(projectActivityHeatmapOffset, maxActivityOffset)
        let showsProjectActivityHeatmapRails = projectActivityChartStyle == .heatmap && maxActivityOffset > 0
        let visibleHeatmapStats: [DailyPromptStat] = {
            guard !heatmapStats.isEmpty else { return [] }
            let fromEnd = activityOff
            let n = min(visibleDayCount, heatmapStats.count)
            let endIndex = heatmapStats.count - fromEnd
            let startIndex = max(endIndex - n, 0)
            return Array(heatmapStats[startIndex..<endIndex])
        }()

        let dateRangeLabel: String = {
            guard let first = barStats.first?.day, let last = barStats.last?.day else { return "" }
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.title3.weight(.semibold))
                Spacer()

                Button {
                    let caption = "📊 \(projectPrompts.count) prompts across \(grouped.count) days — \(project?.name ?? "project")"
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(caption, forType: .string)
                    copiedProjectActivityShare = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedProjectActivityShare = false
                    }
                } label: {
                    Image(systemName: copiedProjectActivityShare ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background {
                            AppControlChrome.glassShareButtonBackground(cornerRadius: 6)
                        }
                }
                .buttonStyle(.plain)
                .help("Share")

                DashboardChartIconSegmentedControl(selection: $projectActivityChartStyle)

                Button("Done") { showProjectActivitySheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(20)

            Divider()

            if grouped.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.quaternary)
                    Text("No activity for this project.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Date range + stats
                    HStack {
                        if projectActivityChartStyle == .bars, !dateRangeLabel.isEmpty {
                            Text(dateRangeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(projectPrompts.count) prompts · \(grouped.count) days")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    // Chart area with optional rails
                    HStack(alignment: .center, spacing: 2) {
                        if showsProjectActivityHeatmapRails {
                            heatmapPanRail(
                                systemName: "chevron.backward",
                                disabled: activityOff >= maxActivityOffset,
                                help: "Earlier days",
                                monthHeaderGutter: 0,
                                gridHeight: 424,
                                railSize: .compactStrip
                            ) {
                                projectActivityHeatmapOffset = min(activityOff + ProviderCardHeatmap.panStepDays, maxActivityOffset)
                            }
                        }

                        Group {
                            if projectActivityChartStyle == .bars {
                                Chart(barStats) { stat in
                                    BarMark(
                                        x: .value("Day", stat.day, unit: .day),
                                        y: .value("Count", stat.count)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(
                                        hoveredActivityBarDay.map { Calendar.current.isDate($0, inSameDayAs: stat.day) } == true
                                            ? dashboardHighlight
                                            : dashboardHighlight.opacity(0.65)
                                    )
                                }
                                .chartYScale(domain: 0...barsMaxY)
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .month)) { _ in
                                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                                .chartYAxis(.hidden)
                                .chartOverlay { proxy in
                                    GeometryReader { geo in
                                        Rectangle()
                                            .fill(.clear)
                                            .contentShape(Rectangle())
                                            .onContinuousHover { phase in
                                                switch phase {
                                                case .active(let loc):
                                                    if let day: Date = proxy.value(atX: loc.x) {
                                                        hoveredActivityBarDay = Calendar.current.startOfDay(for: day)
                                                    }
                                                case .ended:
                                                    hoveredActivityBarDay = nil
                                                }
                                            }
                                    }
                                }
                            } else {
                                DashboardHeatmap(
                                    stats: visibleHeatmapStats,
                                    accent: dashboardHighlight,
                                    compact: false,
                                    fillHorizontalSlack: true,
                                    gridHeight: projectActivityHeatmapGridHeight,
                                    maxSquareSize: 76
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if showsProjectActivityHeatmapRails {
                            heatmapPanRail(
                                systemName: "chevron.forward",
                                disabled: activityOff <= 0,
                                help: "Later days",
                                monthHeaderGutter: 0,
                                gridHeight: 424,
                                railSize: .compactStrip
                            ) {
                                projectActivityHeatmapOffset = max(activityOff - ProviderCardHeatmap.panStepDays, 0)
                            }
                        }
                    }
                    .frame(height: projectActivityChartStyle == .bars ? 340 : 560)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .animation(CodebookMotion.chartStyleSwap, value: projectActivityChartStyle)

                    // Hovered bar tooltip
                    if let hovered = hoveredActivityBarDay,
                       let stat = barStats.first(where: { Calendar.current.isDate($0.day, inSameDayAs: hovered) }) {
                        HStack(spacing: 8) {
                            Text(DateFormatting.displayString(from: stat.day))
                                .font(.system(size: 12, weight: .medium))
                            Text("\(stat.count) prompts")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }

                }
            }
        }
    }

    var historyDateRangePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            datePresetChips
            Divider()
            singleCalendarRangePicker
            if historyDraftStartDate != nil && historyDraftEndDate == nil {
                Text("Now tap an end date")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Divider()
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    dateRangePill(label: "From", date: historyDraftStartDate)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    dateRangePill(label: "To", date: historyDraftEndDate)
                }
                Spacer(minLength: 0)
                if historyDraftStartDate != nil || historyDraftEndDate != nil {
                    Button("Clear") {
                        historyDraftStartDate = nil
                        historyDraftEndDate = nil
                        model.setHistoryFilterStartDate(nil)
                        model.setHistoryFilterEndDate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))
                }
                Button("Done") {
                    showingHistoryDateRangePopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 328)
    }

    func filterControlLabel<Icon: View>(title: String, isActive: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 8) {
            icon()

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppControlChrome.charcoal.opacity(0.72))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppControlChrome.segmentBlue.opacity(0.14))
            } else {
                AppControlChrome.glassShareButtonBackground(cornerRadius: 10)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isActive ? AppControlChrome.segmentBlue.opacity(0.38) : Color.clear,
                    lineWidth: 1
                )
        )
        .foregroundStyle(AppControlChrome.charcoal)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func platformMenuItemLabel(title: String, provider: IntegrationProvider?) -> some View {
        HStack(spacing: 8) {
            if let provider {
                PlatformIconView(provider: provider, size: 14)
            } else {
                AllPlatformsIconView(size: 13)
            }
            Text(title)
        }
    }

    var historyDateRangeLabel: String {
        switch (model.historyFilterStartDate, model.historyFilterEndDate) {
        case let (start?, end?):
            return "\(shortDateString(start)) - \(shortDateString(end))"
        case let (start?, nil):
            return "From \(shortDateString(start))"
        case let (nil, end?):
            return "Until \(shortDateString(end))"
        case (nil, nil):
            return "Date Range"
        }
    }

    func dateRangePill(label: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(date.map(shortDateString) ?? "—")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(date != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
    }

    var datePresetChips: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let lastMonthSeed = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthSeed)) ?? lastMonthSeed
        let lastMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: lastMonthStart) ?? lastMonthStart

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            datePresetChip("Last 7 days",  start: calendar.date(byAdding: .day, value: -6,  to: today) ?? today, end: today)
            datePresetChip("Last 30 days", start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: today)
            datePresetChip("This month",   start: thisMonthStart,  end: today)
            datePresetChip("Last month",   start: lastMonthStart,  end: lastMonthEnd)
        }
    }

    func datePresetChip(_ label: String, start: Date, end: Date) -> some View {
        let calendar = Calendar.current
        let isActive = (historyDraftStartDate.map { calendar.isDate($0, inSameDayAs: start) } ?? false)
            && (historyDraftEndDate.map { calendar.isDate($0, inSameDayAs: end) } ?? false)

        return Button {
            applyDatePreset(start: start, end: end)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    isActive ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor),
                                    lineWidth: 0.5
                                )
                        )
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }

    func applyDatePreset(start: Date, end: Date) {
        let calendar = Calendar.current
        historyDraftStartDate = calendar.startOfDay(for: start)
        historyDraftEndDate = calendar.startOfDay(for: end)
        model.setHistoryFilterStartDate(historyDraftStartDate)
        model.setHistoryFilterEndDate(historyDraftEndDate)
        historyDisplayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
    }

    var singleCalendarRangePicker: some View {
        let calendar = Calendar.current

        return VStack(spacing: 10) {
            HStack {
                Button {
                    historyDisplayedMonth = calendar.date(byAdding: .month, value: -1, to: historyDisplayedMonth) ?? historyDisplayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text(historyDisplayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    historyDisplayedMonth = calendar.date(byAdding: .month, value: 1, to: historyDisplayedMonth) ?? historyDisplayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(historyCalendarDays, id: \.self) { day in
                    historyCalendarDayCell(day)
                }
            }
        }
    }

    var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.shortWeekdaySymbols ?? []
        let calendar = Calendar.current
        let shift = max(0, calendar.firstWeekday - 1)
        return Array(symbols[shift...] + symbols[..<shift]).map { String($0.prefix(2)) }
    }

    var historyCalendarDays: [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: historyDisplayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeekSeed = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthLastWeekSeed) else {
            return []
        }

        var days: [Date?] = []
        var cursor = monthFirstWeek.start
        while cursor < monthLastWeek.end {
            days.append(calendar.isDate(cursor, equalTo: historyDisplayedMonth, toGranularity: .month) ? cursor : nil)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    @ViewBuilder
    func historyCalendarDayCell(_ day: Date?) -> some View {
        if let day {
            let calendar = Calendar.current
            let normalizedDay = calendar.startOfDay(for: day)
            let isToday = calendar.isDateInToday(normalizedDay)
            let isSelected = historyDateIsSelected(normalizedDay)
            let isStart = historyDraftStartDate.map { calendar.isDate(normalizedDay, inSameDayAs: $0) } ?? false
            let isEnd = historyDraftEndDate.map { calendar.isDate(normalizedDay, inSameDayAs: $0) } ?? false
            let isEndpoint = isStart || isEnd
            let hasRange = historyDraftEndDate != nil

            Button {
                selectHistoryDate(normalizedDay)
            } label: {
                // The band and circle sit in the same ZStack so they share the same vertical center.
                // Negative horizontal padding (-2 each side) bridges the 4pt LazyVGrid column gap
                // so the fill looks like one continuous stripe rather than isolated squares.
                ZStack {
                    if isSelected && hasRange && !(isStart && isEnd) {
                        if isStart {
                            HStack(spacing: 0) {
                                Color.clear
                                Color.accentColor.opacity(0.15)
                                    .padding(.trailing, -2)
                            }
                            .frame(height: 26)
                        } else if isEnd {
                            HStack(spacing: 0) {
                                Color.accentColor.opacity(0.15)
                                    .padding(.leading, -2)
                                Color.clear
                            }
                            .frame(height: 26)
                        } else {
                            Color.accentColor.opacity(0.15)
                                .frame(height: 26)
                                .padding(.horizontal, -2)
                        }
                    }

                    Text("\(calendar.component(.day, from: normalizedDay))")
                        .font(.caption.weight(isEndpoint ? .semibold : .medium))
                        .foregroundStyle(isEndpoint ? .white : (isSelected ? Color.accentColor : Color.primary))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(isEndpoint ? Color.accentColor : Color.clear)
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                // Today dot below the circle, via overlay so it doesn't shift the circle's center
                .overlay(alignment: .bottom) {
                    if isToday {
                        Circle()
                            .fill(isEndpoint ? Color.white.opacity(0.7) : Color.accentColor)
                            .frame(width: 3, height: 3)
                            .padding(.bottom, 3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 32)
        }
    }

    func historyDateIsSelected(_ day: Date) -> Bool {
        let calendar = Calendar.current
        guard let start = historyDraftStartDate else { return false }
        let rangeEnd = historyDraftEndDate ?? start
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: rangeEnd)
        return day >= min(normalizedStart, normalizedEnd) && day <= max(normalizedStart, normalizedEnd)
    }

    func selectHistoryDate(_ day: Date) {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)

        switch (historyDraftStartDate, historyDraftEndDate) {
        case (nil, _):
            historyDraftStartDate = normalizedDay
            historyDraftEndDate = nil
            model.setHistoryFilterStartDate(normalizedDay)
            model.setHistoryFilterEndDate(normalizedDay)
        case let (start?, nil):
            let normalizedStart = calendar.startOfDay(for: start)
            historyDraftStartDate = min(normalizedStart, normalizedDay)
            historyDraftEndDate = max(normalizedStart, normalizedDay)
            model.setHistoryFilterStartDate(historyDraftStartDate)
            model.setHistoryFilterEndDate(historyDraftEndDate)
        case let (start?, end?):
            // Adjust whichever endpoint is closer to the tapped date
            let normalizedStart = calendar.startOfDay(for: start)
            let normalizedEnd = calendar.startOfDay(for: end)
            let distToStart = abs(normalizedDay.timeIntervalSince(normalizedStart))
            let distToEnd = abs(normalizedDay.timeIntervalSince(normalizedEnd))
            if distToStart <= distToEnd {
                historyDraftStartDate = min(normalizedDay, normalizedEnd)
                historyDraftEndDate = max(normalizedDay, normalizedEnd)
            } else {
                historyDraftStartDate = min(normalizedStart, normalizedDay)
                historyDraftEndDate = max(normalizedStart, normalizedDay)
            }
            model.setHistoryFilterStartDate(historyDraftStartDate)
            model.setHistoryFilterEndDate(historyDraftEndDate)
        }
    }

    func syncHistoryRangeSelectionFromModel() {
        let calendar = Calendar.current
        historyDraftStartDate = model.historyFilterStartDate
        historyDraftEndDate = model.historyFilterEndDate

        let focusDate = historyDraftStartDate ?? historyDraftEndDate ?? Date()
        historyDisplayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: focusDate)) ?? focusDate
    }

    func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
