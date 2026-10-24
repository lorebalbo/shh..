import AppKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(DashboardModel.self) private var dashboard
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictationEntry.timestamp, order: .reverse) private var entries: [DictationEntry]
    @Query private var styles: [Style]
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showingOriginal: Set<UUID> = []
    @State private var copiedID: UUID?
    @State private var copyResetTask: Task<Void, Never>?
    #if DEBUG
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    #endif

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [DictationEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.rawText.localizedCaseInsensitiveContains(query)
                || (entry.processedText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        PageScaffold(.home) {
            searchField
        } content: {
            history
        }
        #if DEBUG
        .safeAreaInset(edge: .bottom, spacing: 0) { diagnosticPanel }
        #endif
        .onAppear { focusSearchIfRequested() }
        .onChange(of: dashboard.wantsSearchFocus) { focusSearchIfRequested() }
    }

    private func focusSearchIfRequested() {
        guard dashboard.wantsSearchFocus else { return }
        dashboard.wantsSearchFocus = false
        // The field may not be in the window yet when Home has just been opened.
        DispatchQueue.main.async { isSearchFocused = true }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSearchFocused ? Ink.text : Ink.text3)
            TextField("Search dictations", text: $searchText, prompt: Text(""))
                .textFieldStyle(.plain)
                .font(.sans(13.5))
                .foregroundStyle(Ink.text)
                .focused($isSearchFocused)
                .focusEffectDisabled()
                .onExitCommand { searchText = "" }
                .overlay(alignment: .leading) {
                    if searchText.isEmpty {
                        Text("Search")
                            .font(.sans(13.5))
                            .foregroundStyle(Ink.text3)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            if searchText.isEmpty {
                Text("⌘F")
                    .font(.sans(12))
                    .foregroundStyle(Ink.text3)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
            } else {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.onInk)
                        .frame(width: 22, height: 22)
                        .background(Ink.ink, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(width: 220, height: 34)
        .modifier(InkFieldStyle(isFocused: isSearchFocused, shape: Capsule()))
        .contentShape(Capsule())
        .onTapGesture { isSearchFocused = true }
    }

    // MARK: - History

    @ViewBuilder
    private var history: some View {
        if entries.isEmpty {
            EmptyState("No dictations yet", showsMark: true) {
                Text("Hold fn anywhere on your Mac. What you say shows up here.")
            }
        } else if filteredEntries.isEmpty {
            EmptyState("Nothing matches “\(query)”") {
                TextLink("Clear search") { searchText = "" }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groupedByDay.enumerated()), id: \.element.day) { index, group in
                    SectionTitle(dayTitle(group.day))
                        .padding(.top, index == 0 ? 2 : 40)
                        .padding(.bottom, 8)
                    HairlineStack(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var groupedByDay: [(day: Date, entries: [DictationEntry])] {
        let calendar = Calendar.current
        var groups: [(day: Date, entries: [DictationEntry])] = []
        for entry in filteredEntries {
            let day = calendar.startOfDay(for: entry.timestamp)
            if groups.last?.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Entry

    private func styleName(for entry: DictationEntry) -> String? {
        guard let styleId = entry.styleId else { return nil }
        return styles.first { $0.id == styleId }?.name
    }

    private func displayedText(_ entry: DictationEntry) -> String {
        if let processed = entry.processedText, !showingOriginal.contains(entry.id) { return processed }
        return entry.rawText
    }

    private func entryRow(_ entry: DictationEntry) -> some View {
        let isRewritten = entry.processedText != nil
        let isOriginal = isRewritten && showingOriginal.contains(entry.id)
        let styleName = styleName(for: entry)
        let rewrittenVersion = styleName.map { "Show \($0) version" } ?? "Show rewritten version"

        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    copy(entry)
                } label: {
                    Text(highlighted(displayedText(entry)))
                        .font(.sans(15))
                        .lineSpacing(5)
                        .foregroundStyle(isOriginal ? Ink.text2 : Ink.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.vertical, 2.5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy")

                if isRewritten {
                    HStack(spacing: 6) {
                        Text(isOriginal ? "Original transcript" : "Rewritten with \(styleName ?? "a style")")
                        Text("·").accessibilityHidden(true)
                        TextLink(isOriginal ? rewrittenVersion : "Show original", color: Ink.text2) {
                            toggleOriginal(entry)
                        }
                    }
                    .font(.sans(12.5))
                    .foregroundStyle(Ink.text3)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Group {
                    if copiedID == entry.id {
                        HStack(spacing: 6) {
                            InkDrops(motion: .splash, height: 16)
                            Text("Copied").fontWeight(.semibold)
                        }
                        .foregroundStyle(Ink.text)
                    } else {
                        Text(entry.timestamp, format: .dateTime.hour().minute())
                            .monospacedDigit()
                            .foregroundStyle(Ink.text3)
                    }
                }
                .font(.sans(12.5))
                .frame(minWidth: 40, alignment: .trailing)

                RowMenuButton("dictation from \(entry.timestamp.formatted(.dateTime.hour().minute()))") {
                    entryMenuItems(entry, rewrittenVersion: rewrittenVersion)
                }
                .padding(.trailing, -6)
            }
            .frame(height: 23)
        }
        .listRowPadding()
        .contentShape(Rectangle())
        .contextMenu { entryMenuItems(entry, rewrittenVersion: rewrittenVersion) }
    }

    @ViewBuilder
    private func entryMenuItems(_ entry: DictationEntry, rewrittenVersion: String) -> some View {
        Button { copy(entry) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if entry.processedText != nil {
            Button { toggleOriginal(entry) } label: {
                Label(showingOriginal.contains(entry.id) ? rewrittenVersion : "Show original", systemImage: "arrow.left.arrow.right")
            }
        }
        Divider()
        Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
    }

    /// Search matches, marked in the text.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !query.isEmpty else { return attributed }
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lower = AttributedString.Index(match.lowerBound, within: attributed),
               let upper = AttributedString.Index(match.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = Ink.ink
                attributed[lower..<upper].foregroundColor = Ink.paper
            }
            searchRange = match.upperBound..<text.endIndex
        }
        return attributed
    }

    // MARK: - Actions

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedText(entry), forType: .string)
        copiedID = entry.id
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    private func toggleOriginal(_ entry: DictationEntry) {
        if showingOriginal.contains(entry.id) {
            showingOriginal.remove(entry.id)
        } else {
            showingOriginal.insert(entry.id)
        }
    }

    private func delete(_ entry: DictationEntry) {
        let deleted = DeletedEntry(entry)
        modelContext.delete(entry)
        try? modelContext.save()
        let context = modelContext
        dashboard.showToast(Text("Dictation deleted")) {
            deleted.restore(in: context)
        }
    }

    // MARK: - Diagnostic Log

    #if DEBUG
    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDiagnostics.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text("Pipeline Log")
                    if !PipelineEventLog.shared.events.isEmpty {
                        Text("\(PipelineEventLog.shared.events.count)")
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Ink.fill, in: Capsule())
                    }
                    Spacer()
                    if !PipelineEventLog.shared.events.isEmpty {
                        Button("Clear") { PipelineEventLog.shared.clear() }
                            .buttonStyle(.plain)
                    }
                    Image(systemName: showDiagnostics ? "chevron.down" : "chevron.up")
                }
                .font(.sans(12))
                .foregroundStyle(Ink.text3)
                .padding(.horizontal, 44)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                if PipelineEventLog.shared.events.isEmpty {
                    Text("No events yet. Make a recording to see pipeline activity.")
                        .font(.sans(12))
                        .foregroundStyle(Ink.text3)
                        .padding(.horizontal, 44)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(PipelineEventLog.shared.events) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .foregroundStyle(Ink.text3)
                                        .frame(width: 72, alignment: .leading)
                                    Text(event.message)
                                        .foregroundStyle(colorFor(event.kind))
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .font(.inkMono(11))
                            }
                        }
                        .padding(.horizontal, 44)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .background(Ink.paper)
    }

    private func colorFor(_ kind: PipelineEvent.Kind) -> Color {
        switch kind {
        case .info: return Ink.text2
        case .success: return .green
        case .error: return .red
        }
    }
    #endif
}

/// What a deleted dictation needs to come back with Undo.
private struct DeletedEntry {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let processedText: String?
    let styleId: UUID?
    let audioFilePath: String?

    init(_ entry: DictationEntry) {
        id = entry.id
        timestamp = entry.timestamp
        rawText = entry.rawText
        processedText = entry.processedText
        styleId = entry.styleId
        audioFilePath = entry.audioFilePath
    }

    @MainActor
    func restore(in context: ModelContext) {
        let entry = DictationEntry(rawText: rawText, processedText: processedText, styleId: styleId, audioFilePath: audioFilePath)
        entry.id = id
        entry.timestamp = timestamp
        context.insert(entry)
        try? context.save()
    }
}
