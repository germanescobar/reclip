import SwiftUI
import AVKit

struct PostRecordingView: View {
    let fileURL: URL
    @Bindable var manager: RecordingManager
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var editableSegments: [EditableSegment] = []
    @State private var isTranscribing = false
    @State private var transcriptError: String?
    @State private var hasTranscript = false
    @State private var savedLocalURL: URL?
    @State private var player: AVPlayer?
    @FocusState private var isTitleFocused: Bool

    private let transcriptionClient = GroqTranscriptionClient()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                leftPanel
                Divider()
                rightPanel
            }

            Divider()
            bottomBar
        }
        .onAppear {
            player = AVPlayer(url: fileURL)
            isTitleFocused = true
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 16) {
            if let player {
                PlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onAppear { player.play() }
            }

            VStack(spacing: 8) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)

                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 520)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                Spacer()
                if isTranscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }

            if !hasTranscript && !isTranscribing {
                Button("Generate Transcript") {
                    Task { await generateTranscript() }
                }
                .buttonStyle(.bordered)
            }

            if let transcriptError {
                Text(transcriptError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !editableSegments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach($editableSegments) { $segment in
                            SegmentRow(segment: $segment) {
                                seekTo(time: segment.start)
                            }
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else if !hasTranscript {
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 280, idealWidth: 360)
    }

    private func seekTo(time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }

    private var bottomBar: some View {
        HStack {
            Button("Discard") {
                player?.pause()
                try? FileManager.default.removeItem(at: fileURL)
                manager.reset()
                onDismiss()
            }
            .foregroundStyle(.red)

            Spacer()

            if case .uploading = manager.state {
                ProgressView(value: manager.uploadProgress)
                    .frame(width: 120)
                Text("\(Int(manager.uploadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }

            if case .uploaded(let url) = manager.state {
                Link("Open in browser", destination: URL(string: url)!)
                    .font(.callout)

                Button("Done") {
                    manager.reset()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            if let savedLocalURL {
                Text("Saved to \(savedLocalURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if case .error(let msg) = manager.state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            if canAct {
                Button("Save Locally") {
                    saveLocally()
                }
                .buttonStyle(.bordered)

                Button("Upload") {
                    upload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.state == .uploading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var canAct: Bool {
        if case .uploaded = manager.state { return false }
        if case .uploading = manager.state { return false }
        return true
    }

    private func generateTranscript() async {
        isTranscribing = true
        transcriptError = nil

        let result = await transcriptionClient.transcribeIfPossible(fileURL: fileURL)

        isTranscribing = false
        if let result {
            hasTranscript = true
            editableSegments = result.segments.map { EditableSegment(from: $0) }
        } else {
            transcriptError = "Failed to generate transcript. Check your Groq API key in Settings."
        }
    }

    private func upload() {
        player?.pause()
        let recordingTitle = title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title
        let desc = description.isEmpty ? nil : description

        let editedTranscript: RecordingTranscript?
        if !editableSegments.isEmpty {
            let segments = editableSegments.enumerated().map { index, seg in
                TranscriptSegment(id: index, start: seg.start, end: seg.end, text: seg.text)
            }
            let fullText = segments.map(\.text).joined(separator: " ")
            editedTranscript = RecordingTranscript(text: fullText, segments: segments)
        } else {
            editedTranscript = nil
        }

        Task {
            await manager.uploadRecording(
                fileURL: fileURL,
                title: recordingTitle,
                description: desc,
                transcript: editedTranscript
            )
        }
    }

    private func saveLocally() {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.nameFieldStringValue = title.isEmpty ? "recording.mp4" : "\(title).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
            savedLocalURL = destination
        } catch {
            manager.state = .error("Failed to save: \(error.localizedDescription)")
        }
    }
}

private struct EditableSegment: Identifiable {
    let id: Int
    let start: Double
    let end: Double
    var text: String

    init(from segment: TranscriptSegment) {
        self.id = segment.id
        self.start = segment.start
        self.end = segment.end
        self.text = segment.text
    }

    var timestampLabel: String {
        Self.format(start)
    }

    private static func format(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct SegmentRow: View {
    @Binding var segment: EditableSegment
    let onTapTimestamp: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onTapTimestamp) {
                Text(segment.timestampLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 40, alignment: .trailing)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            TextField("", text: $segment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
        }
        .padding(.vertical, 4)
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
