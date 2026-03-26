import SwiftUI
import SwiftData
import AppKit
import AVFoundation

struct HomeView: View {
    @Query(sort: \DictationEntry.timestamp, order: .reverse) private var entries: [DictationEntry]
    @State private var searchText = ""
    @State private var expandedEntryID: UUID?
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    private var filteredEntries: [DictationEntry] {
        if searchText.isEmpty { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            entry.rawText.lowercased().contains(query)
            || (entry.processedText?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            diagnosticPanel
            Divider()
            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(Color.appBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Home")
                .font(Font.appTitle3)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
            Text("\(entries.count) dictation\(entries.count == 1 ? "" : "s")")
                .foregroundStyle(Color.appForeground.opacity(0.5))
                .font(Font.appCallout)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Dictations Yet" : "No Results",
                systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                ? "Your dictation history will appear here."
                : "No dictations match \"\(searchText)\"."
            )
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Diagnostic Log

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDiagnostics.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.caption)
                    Text("Pipeline Log")
                        .font(.caption)
                    if !PipelineEventLog.shared.events.isEmpty {
                        Text("\(PipelineEventLog.shared.events.count)")
                            .font(.caption2)
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    if !PipelineEventLog.shared.events.isEmpty {
                        Button("Clear") { PipelineEventLog.shared.clear() }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                if PipelineEventLog.shared.events.isEmpty {
                    Text("No events yet. Make a recording to see pipeline activity.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(PipelineEventLog.shared.events) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 72, alignment: .leading)
                                    Text(event.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(colorFor(event.kind))
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                }
            }
        }
    }

    private func colorFor(_ kind: PipelineEvent.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                DictationEntryRow(
                    entry: entry,
                    isExpanded: expandedEntryID == entry.id,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedEntryID = (expandedEntryID == entry.id) ? nil : entry.id
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: Text("Search dictations").foregroundStyle(Color.appForeground.opacity(0.4)))
    }
}

// MARK: - Dictation Entry Row

private struct DictationEntryRow: View {
    let entry: DictationEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var selectedTab: EntryTab = .processed

    private enum EntryTab: String, CaseIterable {
        case processed = "Processed"
        case raw = "Original"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(alignment: .center) {
                // Clickable left side
                Button(action: onToggle) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            + Text("  ")
                            + Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Controls (Visible when expanded)
                if isExpanded {
                    HStack(spacing: 12) {
                        if entry.processedText != nil {
                            Picker("View", selection: $selectedTab) {
                                Image(systemName: "wand.and.stars").tag(EntryTab.processed)
                                Image(systemName: "text.alignleft").tag(EntryTab.raw)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .controlSize(.small)
                            .fixedSize()
                            .help("Toggle Processed / Original")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textForTab, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy Text")
                    }
                    .transition(.opacity)
                }

                // Clickable right chevron
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.leading, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            // Text Content
            Text(textForTab)
                .lineLimit(isExpanded ? nil : 2)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
    }

    private var textForTab: String {
        switch selectedTab {
        case .raw:
            return entry.rawText
        case .processed:
            return entry.processedText ?? entry.rawText
        }
    }
}
