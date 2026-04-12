import SwiftUI
import SwiftData
import AppKit
import AVFoundation

struct HomeView: View {
    @Query(sort: \DictationEntry.timestamp, order: .reverse) private var entries: [DictationEntry]
    @State private var searchText = ""
    #if DEBUG
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    #endif

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
            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
            #if DEBUG
            Divider()
            diagnosticPanel
            #endif
        }
        .background(Color.appBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Home")
                .font(Font.appHeadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[.firstTextBaseline] / 2
                }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(Font.appCaption)
                    .foregroundStyle(Color.appForeground.opacity(0.4))
                TextField("", text: $searchText, prompt: Text("Search dictations").foregroundStyle(Color.appForeground.opacity(0.45)))
                    .font(Font.appCallout)
                    .textFieldStyle(.plain)
                    .colorScheme(.light) // Forces the system text field to use dark text/placeholder against our light background
                    .foregroundStyle(Color.appForeground)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Font.appCaption)
                            .foregroundStyle(Color.appForeground.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appForeground.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.appForeground.opacity(0.25))
            Text(searchText.isEmpty ? "No Dictations Yet" : "No Results")
                .font(Font.appTitle3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appForeground)
            Text(
                searchText.isEmpty
                ? "Your dictation history will appear here."
                : "No dictations match \"\(searchText)\"."
            )
            .font(Font.appBody)
            .foregroundStyle(Color.appForeground.opacity(0.45))
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diagnostic Log

    #if DEBUG
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
    #endif

    // MARK: - Entry List

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredEntries) { entry in
                    DictationEntryRow(entry: entry)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .background(Color.appBackground)
    }
}

// MARK: - Dictation Entry Row

private struct DictationEntryRow: View {
    let entry: DictationEntry
    @State private var showingRaw: Bool = false
    @State private var copied: Bool = false
    @State private var isHovered: Bool = false
    @State private var isWandHovered = false
    @State private var isRawHovered = false
    @State private var isTrashHovered = false
    @Environment(\.modelContext) private var modelContext

    private let sideWidth: CGFloat = 120

    private var displayedText: String {
        showingRaw ? entry.rawText : (entry.processedText ?? entry.rawText)
    }

    private var hasProcessed: Bool {
        entry.processedText != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: date and time, one line, right-aligned
            HStack(spacing: 4) {
                Text(entry.timestamp, format: .dateTime.month(.abbreviated).day())
                Text(entry.timestamp, format: .dateTime.hour().minute())
            }
            .font(.caption)
            .foregroundStyle(Color.appForeground.opacity(0.45))
            .lineLimit(1)
            .frame(width: sideWidth, alignment: .trailing)

            // Center: the card
            card.frame(maxWidth: 500)

            // Right: "Copied" indicator, symmetric width to keep card centered
            ZStack(alignment: .leading) {
                if copied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Copied")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.appError)
                    .transition(.opacity)
                }
            }
            .frame(width: sideWidth, alignment: .leading)
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            // Text area — clicking copies
            Button(action: copyText) {
                Text(displayedText)
                    .font(.body)
                    .foregroundStyle(Color.appForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Vertical divider
            Rectangle()
                .fill(Color.appForeground.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 8)

            // Icon controls
            VStack(spacing: 0) {
                // Processed / wand
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showingRaw = false }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(!showingRaw && hasProcessed || isWandHovered
                            ? Color.appError
                            : Color.appForeground.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isWandHovered = $0 }
                .help("Show Processed Text")

                Rectangle()
                    .fill(Color.appForeground.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 8)

                // Raw / original text
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showingRaw = true }
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(showingRaw || !hasProcessed || isRawHovered
                            ? Color.appError
                            : Color.appForeground.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isRawHovered = $0 }
                .help("Show Original Text")

                Rectangle()
                    .fill(Color.appForeground.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 8)

                // Delete
                Button(action: deleteEntry) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isTrashHovered ? Color.appError : Color.appForeground.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isTrashHovered = $0 }
                .help("Delete Entry")
            }
            .frame(width: 56)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 122)
        .background(
            isHovered
                ? Color.appForeground.opacity(0.07)
                : Color.appForeground.opacity(0.03)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered
                        ? Color.appForeground.opacity(0.25)
                        : Color.appForeground.opacity(0.12),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedText, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) { copied = false }
        }
    }

    private func deleteEntry() {
        modelContext.delete(entry)
    }
}
