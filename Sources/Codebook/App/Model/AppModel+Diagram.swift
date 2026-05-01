import Foundation

extension AppModel {

    // MARK: - Architecture Diagram

    /// The model used for diagram generation (gpt-5.4-mini for OpenAI-compatible providers).
    var diagramModel: String {
        selectedInsightsProvider.diagramModel
    }

    func generateDiagram() {
        generateDiagram(kind: .overview)
    }

    func generateDiagram(kind: DiagramKind) {
        loadInsightsApiKeyIfNeeded()
        guard let project = selectedProjectSummary, let path = project.path else {
            diagramError = "Select a project with a local path to generate a diagram."
            return
        }
        let credentials: ResolvedInsightsCredentials
        do {
            credentials = try resolveInsightsCredentials()
        } catch {
            diagramError = error.localizedDescription
            return
        }

        diagramIsGenerating = true
        diagramError = nil
        diagramConversation = []
        diagramGeneratingKind = kind
        diagramUpdatingID = nil
        diagramLastAddedID = nil

        let generator = DiagramGenerator()
        let projectID = project.id
        Task {
            do {
                let context = try generator.scanCodebase(at: path)
                let (system, user) = generator.diagramPrompt(for: kind, context: context)
                let data = try await callDiagramLLM(system: system, userMessage: user, credentials: credentials)
                let responseText = extractAIText(from: data, provider: credentials.provider)
                let svg = generator.extractSVG(from: responseText)

                await MainActor.run {
                    self.diagramCodebaseContext = context
                    if let svg {
                        let diagram = SavedDiagram(projectID: projectID, kind: kind, svgContent: svg)
                        self.savedDiagrams.append(diagram)
                        self.diagramStore.save(self.savedDiagrams)
                        self.diagramSVG = svg
                        self.diagramLastAddedID = diagram.id
                    } else {
                        self.diagramError = "The AI did not return a valid SVG diagram. Try again."
                    }
                    self.diagramIsGenerating = false
                    self.diagramGeneratingKind = nil
                }
            } catch {
                await MainActor.run {
                    self.diagramError = error.localizedDescription
                    self.diagramIsGenerating = false
                    self.diagramGeneratingKind = nil
                }
            }
        }
    }

    func regenerateDiagram() {
        guard let projectID = selectedProjectSummary?.id,
              let index = latestDiagramIndex(for: projectID) else {
            generateDiagram(kind: .overview)
            return
        }
        updateDiagram(id: savedDiagrams[index].id)
    }

    func updateDiagram(id: String) {
        loadInsightsApiKeyIfNeeded()
        guard let index = savedDiagrams.firstIndex(where: { $0.id == id }) else {
            diagramError = "That diagram no longer exists."
            return
        }
        guard let project = projectSummaries.first(where: { $0.id == savedDiagrams[index].projectID }),
              let path = project.path else {
            diagramError = "Select a project with a local path to update this diagram."
            return
        }
        let credentials: ResolvedInsightsCredentials
        do {
            credentials = try resolveInsightsCredentials()
        } catch {
            diagramError = error.localizedDescription
            return
        }

        let kind = savedDiagrams[index].kind
        diagramIsGenerating = true
        diagramError = nil
        diagramGeneratingKind = kind
        diagramUpdatingID = id
        diagramLastAddedID = nil

        let generator = DiagramGenerator()
        Task {
            do {
                let context = try generator.scanCodebase(at: path)
                let (system, user) = generator.diagramPrompt(for: kind, context: context)
                let data = try await callDiagramLLM(system: system, userMessage: user, credentials: credentials)
                let responseText = extractAIText(from: data, provider: credentials.provider)
                let svg = generator.extractSVG(from: responseText)

                await MainActor.run {
                    self.diagramCodebaseContext = context
                    if let svg, let refreshedIndex = self.savedDiagrams.firstIndex(where: { $0.id == id }) {
                        self.savedDiagrams[refreshedIndex].svgContent = svg
                        self.diagramStore.save(self.savedDiagrams)
                        self.diagramSVG = svg
                    } else {
                        self.diagramError = "The AI did not return a valid SVG diagram. Try again."
                    }
                    self.diagramIsGenerating = false
                    self.diagramGeneratingKind = nil
                    self.diagramUpdatingID = nil
                }
            } catch {
                await MainActor.run {
                    self.diagramError = error.localizedDescription
                    self.diagramIsGenerating = false
                    self.diagramGeneratingKind = nil
                    self.diagramUpdatingID = nil
                }
            }
        }
    }

    func askDiagramQuestion(_ question: String) {
        loadInsightsApiKeyIfNeeded()
        guard let projectID = selectedProjectSummary?.id,
              let index = latestDiagramIndex(for: projectID) else {
            diagramError = "Generate a diagram before asking follow-up questions."
            return
        }
        let credentials: ResolvedInsightsCredentials
        do {
            credentials = try resolveInsightsCredentials()
        } catch {
            diagramError = error.localizedDescription
            return
        }

        diagramConversation.append(DiagramMessage(role: .user, content: question))
        diagramQuestionIsRunning = true

        let generator = DiagramGenerator()
        let currentSVG = savedDiagrams[index].svgContent
        let context = diagramCodebaseContext ?? ""
        let currentDiagramID = savedDiagrams[index].id

        Task {
            do {
                let (system, user) = generator.questionPrompt(
                    question: question,
                    currentSVG: currentSVG,
                    codebaseContext: context
                )
                let data = try await callDiagramLLM(system: system, userMessage: user, credentials: credentials)
                let responseText = extractAIText(from: data, provider: credentials.provider)

                await MainActor.run {
                    if generator.responseContainsSVG(responseText),
                       let newSVG = generator.extractSVG(from: responseText) {
                        if let refreshedIndex = self.savedDiagrams.firstIndex(where: { $0.id == currentDiagramID }) {
                            self.savedDiagrams[refreshedIndex].svgContent = newSVG
                            self.diagramStore.save(self.savedDiagrams)
                        }
                        self.diagramSVG = newSVG
                        self.diagramConversation.append(
                            DiagramMessage(role: .assistant, content: "✅ Diagram updated.")
                        )
                    } else {
                        self.diagramConversation.append(
                            DiagramMessage(role: .assistant, content: responseText)
                        )
                    }
                    self.diagramQuestionIsRunning = false
                }
            } catch {
                await MainActor.run {
                    self.diagramConversation.append(
                        DiagramMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
                    )
                    self.diagramQuestionIsRunning = false
                }
            }
        }
    }

    func latestDiagramIndex(for projectID: String) -> Int? {
        savedDiagrams.lastIndex(where: { $0.projectID == projectID })
    }

    /// Call the LLM with the diagram-specific model (gpt-5.4-mini).
    func callDiagramLLM(system: String, userMessage: String, credentials: ResolvedInsightsCredentials) async throws -> Data {
        let transportProvider = credentials.provider
        var request = URLRequest(url: transportProvider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any]
        switch transportProvider.protocolStyle {
        case .openAICompatible:
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": diagramModel,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userMessage]
                ],
                "temperature": 0.3,
                "max_completion_tokens": 8192
            ]

        case .anthropicMessages:
            request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": diagramModel,
                "max_tokens": 8192,
                "system": system,
                "messages": [["role": "user", "content": userMessage]]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw CodebookError.network("Diagram generation failed. \(responseBody.prefix(200))")
        }

        return data
    }

    func selectPrompt(_ prompt: ImportedPrompt) {
        selectedPromptID = prompt.id
        for day in dayGroups {
            if let group = day.groups.first(where: { $0.prompts.contains(where: { $0.id == prompt.id }) }) {
                expandedDayIDs.insert(day.id)
                expandedGroupIDs.insert(group.id)
                break
            }
        }
    }
}
