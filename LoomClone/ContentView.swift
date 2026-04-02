import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @Bindable var manager: RecordingManager
    @State private var selectedDisplay: SCDisplay?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 20) {
            Text("LoomClone")
                .font(.title.bold())

            Text(manager.state.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if manager.isRecording {
                Text(formattedDuration)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.red)

                Text("Drag the floating camera bubble anywhere on the selected display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Display picker
            if !manager.isRecording, case .idle = manager.state {
                if manager.availableDisplays.isEmpty {
                    Button("Load Displays") {
                        Task { await manager.loadDisplays() }
                    }
                } else {
                    Picker("Display", selection: $selectedDisplay) {
                        Text("Select display").tag(nil as SCDisplay?)
                        ForEach(manager.availableDisplays, id: \.displayID) { display in
                            Text("Display \(display.displayID) (\(display.width)x\(display.height))")
                                .tag(display as SCDisplay?)
                        }
                    }
                    .frame(width: 250)
                }
            }

            // Record / Stop button
            Button(action: { Task { await toggleRecording() } }) {
                ZStack {
                    Circle()
                        .fill(manager.isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 72, height: 72)

                    if manager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.red)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 52, height: 52)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(manager.state == .preparing || manager.state == .stopping)

             // Upload button
             if case .saved(let url) = manager.state {
                 HStack(spacing: 12) {
                     Button("Upload to S3") {
                         Task { await manager.uploadRecording(fileURL: url) }
                     }
                     .buttonStyle(.borderedProminent)

                     Button("Open File") {
                         NSWorkspace.shared.open(url)
                     }
                     .buttonStyle(.bordered)

                     Button("Open Folder") {
                         NSWorkspace.shared.open(url.deletingLastPathComponent())
                     }
                     .buttonStyle(.bordered)
                  }

                 Text(url.lastPathComponent)
                     .font(.caption)
                     .foregroundStyle(.secondary)
             }

            // Upload progress
            if manager.state == .uploading {
                ProgressView(value: manager.uploadProgress)
                    .frame(width: 200)
                Text("\(Int(manager.uploadProgress * 100))%")
                    .font(.caption)
            }

            // Uploaded URL
            if case .uploaded(let url) = manager.state {
                Link("Open in browser", destination: URL(string: url)!)
                    .font(.caption)

                Button("New Recording") {
                    manager.reset()
                }
                .buttonStyle(.bordered)
            }

            // Error with retry
            if case .error = manager.state {
                Button("Try Again") {
                    manager.reset()
                }
                .buttonStyle(.bordered)
            }

            Divider()
                .padding(.top, 4)

            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.borderless)

            Button("Quit LoomClone") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(30)
        .frame(minWidth: 350, minHeight: 400)
        .task {
            await manager.loadDisplays()
            if selectedDisplay == nil {
                let initialDisplay = manager.selectedDisplay ?? manager.availableDisplays.first
                selectedDisplay = initialDisplay
                manager.selectedDisplayID = initialDisplay?.displayID
            }
        }
        .onChange(of: selectedDisplay?.displayID) { _, _ in
            manager.selectedDisplayID = selectedDisplay?.displayID
        }
        .sheet(isPresented: $showingSettings) {
            AWSSettingsView()
        }
    }

    private var formattedDuration: String {
        let mins = Int(manager.recordingDuration) / 60
        let secs = Int(manager.recordingDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func toggleRecording() async {
        if manager.isRecording {
            await manager.stopRecording()
        } else {
            guard let display = selectedDisplay ?? manager.availableDisplays.first else {
                manager.state = .error("No display available")
                return
            }
            await manager.startRecording(display: display)
        }
    }
}

private struct AWSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var formData = AWSSettingsStorage.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AWS Settings")
                .font(.title2.bold())

            Form {
                TextField("Access Key ID", text: $formData.accessKeyId)
                    .textFieldStyle(.roundedBorder)

                SecureField("Secret Access Key", text: $formData.secretAccessKey)
                    .textFieldStyle(.roundedBorder)

                SecureField("Session Token (optional)", text: $formData.sessionToken)
                    .textFieldStyle(.roundedBorder)

                TextField("Region", text: $formData.region)
                    .textFieldStyle(.roundedBorder)

                TextField("Bucket", text: $formData.bucket)
                    .textFieldStyle(.roundedBorder)

                Toggle("Use public object URLs", isOn: $formData.usePublicURLs)

                if formData.usePublicURLs {
                    TextField("Public Base URL (optional)", text: $formData.publicBaseURL)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Presigned URL Expiration (seconds)", text: $formData.presignedURLExpiration)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    AWSSettingsStorage.save(formData)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
