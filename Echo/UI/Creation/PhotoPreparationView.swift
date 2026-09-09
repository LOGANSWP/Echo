// Task 4.0l; US-ING-004 AC-7/8: local machine material with visible recovery.
import SwiftUI

struct PhotoPreparationView: View {
    private let onReadinessChange: (Bool) -> Void
    @State private var model: PhotoPreparationViewModel
    @State private var refreshID = 0
    @State private var preparationRequested = false

    init(memoryID: UUID, service: any PhotoPreparationServicing, onReadinessChange: @escaping (Bool) -> Void = { _ in }) {
        self.onReadinessChange = onReadinessChange
        _model = State(initialValue: PhotoPreparationViewModel(memoryID: memoryID, service: service))
    }

    var body: some View {
        EchoContainer(level: .section) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                Label("Photo understanding", systemImage: "photo.badge.checkmark")
                    .font(EchoTypographyToken.metadata.font)
                switch model.state {
                case .idle, .loading, .completed(.queued):
                    ProgressView("Preparing photo material")

                case .completed(.ready):
                    if let material = model.material {
                        if material.usesUserCorrection {
                            Text("Your description is used for creation.")
                        } else {
                            Text("AI image description (English original)")
                                .font(EchoTypographyToken.metadata.font)
                            Text(verbatim: material.caption)
                                .accessibilityIdentifier("photo-understanding-caption")
                            Text("Machine-generated; may contain mistakes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("OCR text")
                            .font(EchoTypographyToken.metadata.font)
                        if let text = material.ocrText, !text.isEmpty {
                            Text(verbatim: text)
                                .accessibilityIdentifier("photo-understanding-ocr")
                        } else {
                            Text("No text was recognized in this photo.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(
                        "On-device image description and available image text are ready for creation. Machine descriptions can be corrected in memory details."
                    )
                    .foregroundStyle(.secondary)

                case .completed(.unprepared):
                    Text("Prepare this photo on device to create from its image. A written description is optional.")
                    prepareButton

                case .completed(.failed), .completed(.unavailable), .error:
                    Text(
                        "Photo preparation is unavailable or failed. Check photo access and local model availability, then retry."
                    )
                    prepareButton
                }
            }
        }
        .accessibilityIdentifier("photo-preparation-status")
        .onChange(of: model.canCreate, initial: true) { _, ready in onReadinessChange(ready) }
        .task(id: refreshID) {
            let shouldPrepare = preparationRequested
            preparationRequested = false
            if shouldPrepare { await model.prepare() } else { await model.prepareOnAccess() }
            await pollQueuedWork()
        }
    }

    private var prepareButton: some View {
        Button("Prepare or retry photo") {
            preparationRequested = true
            refreshID += 1
        }
        .buttonStyle(EchoActionButtonStyle(role: .recovery))
        .accessibilityIdentifier("photo-preparation-retry")
    }

    private func pollQueuedWork() async {
        while model.state == .completed(.queued), !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await model.refresh()
        }
    }
}
