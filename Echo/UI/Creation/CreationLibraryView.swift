// File: CreationLibraryView.swift
// Spec: US-SYN-003 AC-8/9/10; ADR-026
// Task: 4.0m - Native Task list and Focus result routing
import SwiftUI

@MainActor
@Observable
final class CreationLibraryViewModel {
    deinit {}
    enum Filter: String, CaseIterable {
        case all = "All creations"
        case active = "In progress"
        case completed = "Completed"
        case failed = "Needs attention"
    }
    var filter = Filter.all
    private(set) var records: [CreationLibraryRecord] = []
    private(set) var reports: [PersistedNarrativeReport] = []
    private(set) var error = false
    private(set) var loading = false
    private(set) var deletingIDs: Set<UUID> = []
    var deletionError = false
    let library: CreationLibraryActor
    let reportActor: NarrativeReportActor

    init(library: CreationLibraryActor, reportActor: NarrativeReportActor) {
        self.library = library
        self.reportActor = reportActor
    }

    var filteredRecords: [CreationLibraryRecord] {
        records.filter {
            switch filter {
            case .all: true
            case .active: [.submitting, .queued, .running, .deferred].contains($0.state)
            case .completed: $0.state == .completed
            case .failed: [.failed, .cancelled, .interrupted].contains($0.state)
            }
        }
    }

    struct Entry: Identifiable {
        let id: UUID
        let createdAt: Date
        let record: CreationLibraryRecord?
        let report: PersistedNarrativeReport?
    }

    var entries: [Entry] {
        let manual = filteredRecords.map { Entry(id: $0.id, createdAt: $0.createdAt, record: $0, report: nil) }
        let automatic = (filter == .all || filter == .completed ? reports : []).map {
            Entry(id: $0.id, createdAt: $0.createdAt, record: nil, report: $0)
        }
        return (manual + automatic).sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            records = try await library.list()
            reports = try await reportActor.listReports()
            error = false
        } catch {
            records = []
            reports = []
            self.error = true
        }
    }

    func retry(_ id: UUID) async {
        loading = true
        do { try await library.retry(id: id); await refresh() } catch { self.error = true; loading = false }
    }

    func cancel(_ id: UUID) async {
        loading = true
        do { try await library.cancel(id: id); await refresh() } catch { self.error = true; loading = false }
    }

    func delete(_ id: UUID) async {
        loading = true
        guard deletingIDs.insert(id).inserted else { return }
        defer { deletingIDs.remove(id); loading = false }
        do {
            if reports.contains(where: { $0.id == id }) {
                try await reportActor.deleteReport(reportID: id)
            } else {
                try await library.delete(id: id)
            }
            deletionError = false
            await refresh()
        } catch {
            deletionError = true
        }
    }
}

struct CreationLibraryView: View {
    @State private var model = CreationLibraryViewModel(library: AppComposition.shared.creationLibraryActor, reportActor: AppComposition.shared.narrativeReportActor)

    @State private var pendingDeletion: CreationLibraryViewModel.Entry?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        List {
            Picker("Filter", selection: $model.filter) {
                ForEach(CreationLibraryViewModel.Filter.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            if model.error {
                Text("Could not load creations. Please try again.")
                Button("Retry") { Task { await model.refresh() } }
            }
            if model.loading && model.entries.isEmpty { ProgressView() }
            if model.entries.isEmpty && !model.error && !model.loading {
                Text("Your creations will appear here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.entries) { entry in
                HStack(alignment: .top) {
                    entryContent(entry)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Delete", role: .destructive) { requestDeletion(entry) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("More actions")
                    .accessibilityIdentifier("creation-library-actions-\(entry.id)")
                    .disabled(model.deletingIDs.contains(entry.id))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { requestDeletion(entry) }
                        .accessibilityIdentifier("creation-library-delete-\(entry.id)")
                        .disabled(model.deletingIDs.contains(entry.id))
                }
            }
        }
        .navigationTitle("Creation Library")
        .tint(EchoColorToken.warmAccent.color)
        .confirmationDialog(
            "Delete this creation?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) {
                pendingDeletion = nil
                Task { await model.delete(entry.id) }
            }
            .accessibilityIdentifier("creation-library-confirm-delete")
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { entry in
            if entry.report != nil {
                Text("This deletes only this report. Your source memories will be kept. This report will not be generated again automatically.")
            } else {
                Text("This deletes only this creation and cancels any active generation. Your source memories will be kept.")
            }
        }
        .alert("Could not delete creation", isPresented: $model.deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The creation has been kept. Please try deleting it again.")
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .refreshable { await model.refresh() }
    }

    private func requestDeletion(_ entry: CreationLibraryViewModel.Entry) {
        pendingDeletion = entry
        showsDeleteConfirmation = true
    }

    @ViewBuilder
    private func entryContent(_ entry: CreationLibraryViewModel.Entry) -> some View {
        if let record = entry.record {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    LibraryCreationDetail(id: record.id)
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            if let title = record.output?.title { Text(title) } else { Text(LocalizedStringKey(record.request.template.rawValue.capitalized)) }
                            if record.unread { Image(systemName: "circle.fill").font(.caption2).accessibilityLabel("New creation") }
                        }
                        Text(record.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        Text(stateLabel(record.state)).font(.caption).foregroundStyle(.secondary)
                        if let code = record.errorCode { Text(errorLabel(code)).font(.caption) }
                    }
                }
                if [.failed, .cancelled, .interrupted, .deferred].contains(record.state) {
                    Button(record.state == .deferred ? "Continue" : "Retry") { Task { await model.retry(record.id) } }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("creation-library-retry-\(record.id)")
                        .disabled(model.loading || model.deletingIDs.contains(record.id))
                }
                if [.queued, .running].contains(record.state) {
                    Button("Cancel") { Task { await model.cancel(record.id) } }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("creation-library-cancel-\(record.id)")
                        .disabled(model.deletingIDs.contains(record.id))
                }
            }
        } else if let report = entry.report {
            NavigationLink { LibraryReportDetail(id: report.id) } label: { Text(report.envelope.title) }
        }
    }

    private func errorLabel(_ code: String) -> LocalizedStringKey {
        switch code {
        case "deadline": "Generation reached the time limit on this device. Try a shorter memory."
        case "output-limit": "The model reached the output limit before completing this creation. Please try again."
        case "language": "The model could not produce a complete response in your selected language. Please try again."
        case "model-unavailable": "Offline generation runtime is not available. Please try again."
        case "interrupted": "Interrupted — retry to start again"
        default: "Generation is currently unavailable. Please try again."
        }
    }

    private func stateLabel(_ state: CreationLibraryState) -> LocalizedStringKey {
        switch state {
        case .deferred: "Waiting for device resources"
        case .submitting: "Submitting"
        case .queued: "Queued"
        case .running: "Creating"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted — retry to start again"
        }
    }
}

private struct LibraryCreationDetail: View {
    let id: UUID
    @State private var model = CreationViewModel(
        exportCoordinator: AppComposition.shared.creationExportCoordinator,
        creationLibrary: AppComposition.shared.creationLibraryActor
    )
    var body: some View {
        CreationView(viewModel: model, returnsToLibrary: true)
            .task { await model.observeLibraryRequest(id) }
    }
}

private struct LibraryReportDetail: View {
    let id: UUID
    @State private var model = CreationViewModel(
        exportCoordinator: AppComposition.shared.creationExportCoordinator,
        narrativeReportActor: AppComposition.shared.narrativeReportActor
    )
    var body: some View {
        CreationView(viewModel: model, returnsToLibrary: true)
            .task { model.openReport(id) }
    }
}
