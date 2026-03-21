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
                .font(Font.appLargeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(Font.appBody)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                TextField("Search dictations", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.appForeground)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Font.appBody)
                            .foregroundStyle(Color.appForeground.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appForeground.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 250)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Dictations Yet" : "No Results",
                systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass"
            )
            .foregroundStyle(Color.appForeground)
        } description: {
            Text(
                searchText.isEmpty
                ? "Your dictation history will appear here."
                : "No dictations match \"\(searchText)\"."
            )
            .foregroundStyle(Color.appForeground.opacity(0.8))
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Pipeline Log Removed


    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                DictationEntryRow(
                    entry: entry,
                    isExpanded: expandedEntryID == entry.id,
                    onToggle: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            expandedEntryID = (expandedEntryID == entry.id) ? nil : entry.id
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: expandedEntryID)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timestamp, style: .date)
                        .font(Font.appCaption)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                    + Text("  ")
                    + Text(entry.timestamp, style: .time)
                        .font(Font.appCaption)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                }
                Spacer()

                // Controls always visible
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
                        .onTapGesture { } // Prevent row tap from firing on picker
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(textForTab, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(Font.appTitle3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
                    .help("Copy Text")
                }
            }
            .padding(.bottom, 6)

            // Text Content
            Text(textForTab)
                .lineLimit(isExpanded ? nil : 2)
                .font(Font.appBody)
                .textSelection(.enabled)
                .foregroundStyle(Color.appForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(isExpanded)
        }
        .padding(12)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(Color.appForeground.opacity(0.1), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
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
