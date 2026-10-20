import SwiftUI

// The Slack-style side panel (Jian: "similar to Slack but shows folders and
// session names"): swipe in from the left edge of a session to see every
// session, filed by folder, with what each one needs at a glance — and jump
// straight to another without going back to the wall. The ‹ button in the
// bar remains the way back; the drawer's "All sessions" row goes there too.
struct SessionDrawer: View {
    let currentInternal: String
    var onPick: (String) -> Void
    var onAllSessions: () -> Void
    var onClose: () -> Void

    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var scope: SessionScope = .user
    /// Folder ids the reader has folded ("" = Unfiled), persisted.
    @AppStorage("drawerCollapsed") private var collapsedRaw = ""
    @State private var parkedOpen = false
    /// The drawer's OWN arrangement, separate from the wall's (Jian: "same
    /// ordering options as the session view but do not need to be
    /// identical"). Folders by default — the Slack sidebar shape.
    @AppStorage("drawerOrder") private var orderRaw = GroupMode.folder.rawValue
    private var order: GroupMode { GroupMode(rawValue: orderRaw) ?? .folder }
    @State private var drag: CGFloat = 0
    /// When the last sideways swipe moved. The close drag runs alongside the
    /// list (simultaneous), so a swipe that STARTS and ENDS on one full-width
    /// row also reads as a tap on it — the swipe that closed the drawer
    /// opened whatever session was under the finger. Taps right after a
    /// swipe are ignored.
    @State private var swipedAt = Date.distantPast
    private var justSwiped: Bool { Date().timeIntervalSince(swipedAt) < 0.5 }
    @FocusState private var filterFocused: Bool

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private func toggle(_ id: String) {
        var c = collapsed
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        collapsedRaw = c.sorted().joined(separator: ",")
    }

    private var visible: [HopSession] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return model.sessions
            .filter { !$0.isPort && matchesScope($0.createdBy, scope) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.tagline.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// (section id, title, sessions) in the chosen arrangement. Parked
    /// sessions are kept for their own folded section. Section ids carry the
    /// mode so folding "Active" doesn't fold a folder of the same name.
    private var groups: [(id: String, title: String, rows: [HopSession])] {
        let active = visible.filter { !$0.parked || !filter.isEmpty }
        let byRecency = active.sorted { $0.lastActivityAt > $1.lastActivityAt }
        if !filter.isEmpty { return [("", "Matches", active)] }
        switch order {
        case .recent:
            return [("recent:", "Recent", byRecency)]
        case .used:
            return groupSessionsByUse(active).map { ("used:" + $0.label, $0.label, $0.rows) }
        case .project:
            return groupSessionsByProject(active).map { ("project:" + $0.label, $0.label, $0.rows) }
        case .folder:
            var out: [(String, String, [HopSession])] = []
            let known = Set(model.folders.map(\.id))
            for f in model.folders {
                let rows = active.filter { $0.folderId == f.id }
                if !rows.isEmpty { out.append((f.id, f.name, rows)) }
            }
            let unfiled = active.filter { $0.folderId == nil || !known.contains($0.folderId!) }
            if !unfiled.isEmpty { out.append(("", model.folders.isEmpty ? "Sessions" : "Unfiled", unfiled)) }
            return out
        }
    }
    private var parked: [HopSession] { filter.isEmpty ? visible.filter(\.parked) : [] }

    var body: some View {
        GeometryReader { g in
            // Portrait phone: the whole screen (Jian: "might as well be full
            // screen in portrait since it already covers most of it").
            // Landscape / iPad: a side panel over the session.
            let full = g.size.height > g.size.width && g.size.width < 500
            let width = full ? g.size.width : min(330, g.size.width * 0.86)
            ZStack(alignment: .leading) {
                Color.black.opacity(0.35 * (1 - min(1, -drag / width)))
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }
                    // A leftward swipe over the dimmed session closes too.
                    .gesture(closeDrag(width))
                    .accessibilityLabel("Close session list")
                    .accessibilityAddTraits(.isButton)
                panel(full: full)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(Color.hopSurface.ignoresSafeArea())
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.hopLine(0.12)).frame(width: 0.5).ignoresSafeArea()
                    }
                    .offset(x: min(0, drag))
                    // Swipe it back to the left to close. Simultaneous, not
                    // .gesture: the ScrollView's pan and the row buttons
                    // otherwise swallow the drag, so it only worked on the
                    // header (Jian: "should have a gesture to close").
                    .simultaneousGesture(closeDrag(width))
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 4)
            }
        }
        .onAppear { scope = model.swipeScope }
    }

    /// Leftward drag that follows the finger and closes past 30% (or a
    /// flick). Global space: the panel moves with the drag (the
    /// floating-card lesson). Vertical drags are left to the list.
    private func closeDrag(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                swipedAt = Date()
                drag = min(0, v.translation.width)
            }
            .onEnded { v in
                let sideways = abs(v.translation.width) > abs(v.translation.height)
                if sideways && (v.translation.width < -width * 0.3 || v.predictedEndTranslation.width < -width * 0.6) {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
            }
    }

    private func panel(full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if full {
                        // Full screen leaves no dimmed edge to tap away.
                        Button { onClose() } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close session list")
                        .accessibilityIdentifier("drawer close")
                    }
                    Text("Sessions").font(.headline)
                    Menu {
                        Picker("Arrange", selection: $orderRaw) {
                            ForEach(GroupMode.allCases, id: \.self) { m in
                                Label(m == .project ? "Project" : m == .folder ? "Folder" : m.label,
                                      systemImage: m.icon).tag(m.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: order.icon)
                            .font(.subheadline)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Arrange: \(order.label)")
                    .accessibilityIdentifier("drawer arrange")
                    Spacer()
                    Picker("Scope", selection: $scope) {
                        ForEach(SessionScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Jump to…", text: $filter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($filterFocused)
                        .submitLabel(.go)
                        .onSubmit { if let first = visible.first { onPick(first.internalName) } }
                        .accessibilityIdentifier("drawer filter")
                    if !filter.isEmpty {
                        Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).frame(height: 34)
                .background(Color.hopPill, in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Button { if !justSwiped { onAllSessions() } } label: {
                        Label("All sessions", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("drawer all sessions")

                    ForEach(groups, id: \.id) { group in
                        folderHeader(group.id, group.title, group.rows)
                        if !collapsed.contains(group.id) || !filter.isEmpty {
                            ForEach(group.rows) { row($0) }
                        }
                    }
                    if !parked.isEmpty {
                        Button { withAnimation(.easeOut(duration: 0.18)) { parkedOpen.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: parkedOpen ? "chevron.down" : "chevron.right").font(.caption2.weight(.bold))
                                Text("Parked · \(parked.count)").font(.caption.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if parkedOpen { ForEach(parked) { row($0) } }
                    }
                    if visible.isEmpty {
                        Text(filter.isEmpty ? "No sessions in this scope." : "No session matches “\(filter)”.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func folderHeader(_ id: String, _ title: String, _ rows: [HopSession]) -> some View {
        let wanting = rows.filter(\.attention).count
        let folded = collapsed.contains(id) && filter.isEmpty
        return Button { if !justSwiped { withAnimation(.easeOut(duration: 0.18)) { toggle(id) } } } label: {
            HStack(spacing: 6) {
                Image(systemName: folded ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .frame(width: 10)
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer()
                // Folded, a folder still says if something inside wants you.
                if folded && wanting > 0 {
                    Text("\(wanting)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.hopAttention, in: Capsule())
                        .foregroundStyle(.black)
                } else {
                    Text("\(rows.count)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(rows.count) sessions\(wanting > 0 ? ", \(wanting) want you" : "")")
    }

    private func row(_ s: HopSession) -> some View {
        let current = s.internalName == currentInternal
        let dot: Color = s.attention ? .hopAttention
            : (phaseTint(s.phase) ?? (s.live ? Color.hopLive.opacity(0.7) : Color.secondary.opacity(0.35)))
        return Button { if !justSwiped { onPick(s.internalName) } } label: {
            HStack(spacing: 9) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(s.name)
                    .font(.system(.subheadline, design: .monospaced).weight(s.attention || current ? .semibold : .regular))
                    .foregroundStyle(s.live ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if s.parked {
                    Image(systemName: "moon.zzz").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("parked mark")
                }
                if ViewSeen.isNew(s) {
                    Image(systemName: "sparkles").font(.caption2).foregroundStyle(Color.hopGlow)
                        .accessibilityLabel("new result")
                }
                if s.checkbacks > 0 {
                    Text("⏰\(s.checkbacks)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(current ? Color.hopGlow.opacity(0.16) : Color.clear)
            .overlay(alignment: .leading) {
                if current { Rectangle().fill(Color.hopGlow).frame(width: 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Triage from the drawer, Slack's long-press on a channel.
        .contextMenu {
            Button {
                Task { _ = await model.setParked(s, parked: !s.parked) }
            } label: {
                Label(s.parked ? "Unpark" : "Park", systemImage: s.parked ? "sun.max" : "moon.zzz")
            }
        }
        .accessibilityLabel("\(s.name)\(s.attention ? ", wants you" : "")\(current ? ", current" : "")\(s.parked ? ", parked" : "")")
        // A row with a .contextMenu kept its first rendering: the body re-ran
        // with parked=true (traced) while the screen still showed it unparked.
        // Folding the state into the identity rebuilds the row when it flips.
        .id("\(s.internalName)|\(s.parked)|\(s.attention)|\(current)")
        .accessibilityIdentifier("drawer row \(s.name)")
    }
}
