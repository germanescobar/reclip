import SwiftUI
import ScreenCaptureKit
import AVFoundation

struct ContentView: View {
    @Bindable var manager: RecordingManager
    var authManager: AuthManager
    @State private var selectedDisplay: SCDisplay?
    @State private var selectedCameraID: String?
    @State private var selectedMicrophoneID: String?
    @State private var showingSettings = false
    @State private var recordingTitle = ""
    @State private var recordingDescription = ""

    var body: some View {
        Group {
            if authManager.isSignedIn {
                signedInView
            } else {
                signedOutView
            }
        }
        .frame(minWidth: 350, minHeight: 460)
    }

    private var signedOutView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Reclip")
                .font(.title.bold())

            Text("Sign in to start recording")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Sign In with Browser") {
                authManager.signIn()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()

            Button("Quit Reclip") {
                manager.quitApplication()
            }
            .buttonStyle(.borderless)
        }
        .padding(30)
    }

    private var signedInView: some View {
        VStack(spacing: 20) {
            Text("Reclip")
                .font(.title.bold())

            Text(manager.state.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !manager.permissionsReady {
                permissionsSetupView
            } else {
                recordingControlsView
            }

            Divider()
                .padding(.top, 4)

            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.borderless)

            Button("Quit Reclip") {
                manager.quitApplication()
            }
            .buttonStyle(.borderless)
        }
        .padding(30)
        .task {
            await manager.prepare()
            syncLocalSelections()
        }
        .onChange(of: selectedDisplay?.displayID) { _, _ in
            manager.selectedDisplayID = selectedDisplay?.displayID
        }
        .onChange(of: selectedCameraID) { _, newValue in
            manager.selectedCameraID = newValue
        }
        .onChange(of: selectedMicrophoneID) { _, newValue in
            manager.selectedMicrophoneID = newValue
        }
        .sheet(isPresented: $showingSettings) {
            AWSSettingsView(authManager: authManager)
        }
    }

    private var permissionsSetupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before the first recording, let’s enable permissions one step at a time.")
                .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    title: "1. Camera and microphone",
                    isComplete: manager.cameraPermissionGranted && manager.microphonePermissionGranted,
                    description: "Enable camera and microphone access first so the preview bubble can work."
                )

                if !(manager.cameraPermissionGranted && manager.microphonePermissionGranted) {
                    Button("Allow Camera and Microphone") {
                        Task {
                            await manager.requestCameraAndMicrophonePermissions()
                            syncLocalSelections()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    title: "2. Screen recording",
                    isComplete: manager.screenPermissionGranted && !manager.needsAppRestart,
                    description: "Grant screen recording only after camera and microphone are ready."
                )

                if manager.canRequestScreenPermission && !manager.screenPermissionGranted {
                    Button("Request Screen Recording Access") {
                        manager.beginScreenRecordingPermissionFlow()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if manager.canRequestScreenPermission && !manager.screenPermissionGranted {
                    Button("Open Screen Recording Settings") {
                        manager.openScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)
                }

                if manager.needsAppRestart {
                    Text("macOS applies screen recording access after Reclip quits. Turn it on in System Settings, then reopen the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Quit and Reopen Reclip") {
                        manager.quitApplication()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("Refresh Permission Status") {
                Task {
                    await manager.prepare()
                    syncLocalSelections()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingControlsView: some View {
        Group {
            if manager.isRecording {
                Text(formattedDuration)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.red)

                Text("Drag the floating camera bubble anywhere on the selected display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !manager.isRecording, case .idle = manager.state {
                if manager.availableDisplays.isEmpty {
                    Button("Load Displays") {
                        Task {
                            await manager.loadDisplays()
                            syncLocalSelections()
                        }
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

                if !manager.availableCameras.isEmpty {
                    Picker("Camera", selection: $selectedCameraID) {
                        ForEach(manager.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera.uniqueID as String?)
                        }
                    }
                    .frame(width: 250)
                }

                if !manager.availableMicrophones.isEmpty {
                    Picker("Microphone", selection: $selectedMicrophoneID) {
                        ForEach(manager.availableMicrophones, id: \.uniqueID) { mic in
                            Text(mic.localizedName).tag(mic.uniqueID as String?)
                        }
                    }
                    .frame(width: 250)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone Check")
                        .font(.headline)

                    HStack(spacing: 10) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(microphoneMeterColor)
                                    .frame(width: max(manager.microphoneLevel * 180, 6))
                            }
                            .frame(width: 180, height: 10)

                        Text(manager.microphoneCheckState.displayText)
                            .font(.caption)
                            .foregroundStyle(microphoneCheckTextColor)
                    }

                    Button(manager.microphoneCheckState == .checking ? "Checking..." : "Test Microphone") {
                        Task {
                            await manager.runMicrophoneCheckManually()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.microphoneCheckState == .checking || manager.state == .preparing)
                }
                .frame(width: 250, alignment: .leading)
            }

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

            if case .saved(let url) = manager.state {
                VStack(spacing: 8) {
                    TextField("Title", text: $recordingTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)

                    TextField("Description (optional)", text: $recordingDescription)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                }

                HStack(spacing: 12) {
                    Button("Upload") {
                        let title = recordingTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : recordingTitle
                        Task { await manager.uploadRecording(fileURL: url, title: title, description: recordingDescription.isEmpty ? nil : recordingDescription) }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Discard") {
                        try? FileManager.default.removeItem(at: url)
                        manager.reset()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }

                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if manager.state == .uploading {
                ProgressView(value: manager.uploadProgress)
                    .frame(width: 200)
                Text("\(Int(manager.uploadProgress * 100))%")
                    .font(.caption)
            }

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
        }
    }

    private var formattedDuration: String {
        let mins = Int(manager.recordingDuration) / 60
        let secs = Int(manager.recordingDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    @ViewBuilder
    private func permissionRow(title: String, isComplete: Bool, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(isComplete ? "Ready" : "Pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isComplete ? .green : .secondary)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func syncLocalSelections() {
        selectedDisplay = manager.selectedDisplay
        selectedCameraID = manager.selectedCameraID
        selectedMicrophoneID = manager.selectedMicrophoneID
    }

    private var microphoneMeterColor: Color {
        switch manager.microphoneCheckState {
        case .ready:
            return .green
        case .failed:
            return .orange
        default:
            return .blue
        }
    }

    private var microphoneCheckTextColor: Color {
        switch manager.microphoneCheckState {
        case .ready:
            return .green
        case .failed:
            return .orange
        default:
            return .secondary
        }
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
    var authManager: AuthManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.bold())

            Form {
                Section("Account") {
                    if authManager.isSignedIn {
                        HStack {
                            Text("Signed in")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Sign Out") {
                                authManager.signOut()
                                dismiss()
                            }
                        }
                    } else {
                        Button("Sign In with Browser") {
                            AWSSettingsStorage.save(formData)
                            authManager.signIn()
                            dismiss()
                        }
                    }
                }

                Section("AWS") {
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
