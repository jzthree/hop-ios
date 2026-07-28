import AppIntents

// The fleet, exposed to Siri and Shortcuts. AppIntents run inside the app's
// own process (launched in the background when needed), so the entities can
// read AppModel directly — no extension, no app group, no signing changes:
// the same cookie the app holds authenticates the refresh.

struct SessionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "hop Session")
    static let defaultQuery = SessionQuery()

    var id: String
    var name: String
    var tagline: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: tagline.isEmpty ? nil : "\(tagline)")
    }
}

struct SessionQuery: EntityQuery {
    /// Cold background launches arrive with an empty model; one silent
    /// refresh fills it from the daemon before the picker renders.
    @MainActor
    private func fleet() async -> [SessionEntity] {
        let model = AppModel.shared
        if model.sessions.isEmpty { await model.refreshSessions(silent: true) }
        return model.sessions.filter { !$0.isPort && !$0.parked }
            .map { SessionEntity(id: $0.internalName, name: $0.name, tagline: $0.tagline) }
    }

    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        await fleet().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        await fleet()
    }
}

struct OpenSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Session"
    static let description = IntentDescription("Jump straight into a hop terminal session.")
    static let openAppWhenRun = true

    @Parameter(title: "Session")
    var session: SessionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        // The same road Spotlight and notification taps travel — the pending
        // consume path handles cold launch.
        AppModel.shared.requestedSession = session.id
        return .result()
    }
}

struct FleetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Fleet Status"
    static let description = IntentDescription("How many sessions are running, and whether any want you.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        await model.refreshSessions(silent: true)
        let browsable = model.sessions.filter { !$0.isPort && !$0.parked }
        let line = fleetStatusLine(wanting: browsable.filter(\.attention).count,
                                   total: browsable.count)
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct HopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenSessionIntent(),
                    phrases: ["Open a session in \(.applicationName)"],
                    shortTitle: "Open Session",
                    systemImageName: "terminal")
        AppShortcut(intent: FleetStatusIntent(),
                    phrases: ["\(.applicationName) status",
                              "Check my \(.applicationName) sessions"],
                    shortTitle: "Fleet Status",
                    systemImageName: "dot.radiowaves.left.and.right")
    }
}
