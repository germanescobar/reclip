import SwiftUI
import ScreenCaptureKit
import AVFoundation

struct ContentView: View {
    @Bindable var manager: RecordingManager
    var authManager: AuthManager
    @State private var selectedDisplay: SCDisplay?
    @State private var captureMode: RecordingCaptureMode = .display
    @State private var selectedWindowID: CGWindowID?
    @State private var areaX: Double = 0
    @State private var areaY: Double = 0
    @State private var areaWidth: Double = 1280
    @State private var areaHeight: Double = 720
    @State private var showingSettings = false

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

            recordingControlsView

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
        .onChange(of: captureMode) { _, newValue in
            manager.captureMode = newValue
        }
        .onChange(of: selectedWindowID) { _, newValue in
            manager.selectedWindowID = newValue
        }
        .onChange(of: areaX) { _, _ in syncAreaSelection() }
        .onChange(of: areaY) { _, _ in syncAreaSelection() }
        .onChange(of: areaWidth) { _, _ in syncAreaSelection() }
        .onChange(of: areaHeight) { _, _ in syncAreaSelection() }
        .sheet(isPresented: $showingSettings) {
            AWSSettingsView(authManager: authManager)
        }
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
                Picker("Capture", selection: $captureMode) {
                    ForEach(RecordingCaptureMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

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

                if captureMode == .window {
                    if manager.availableWindows.isEmpty {
                        Button("Load Windows") {
                            Task {
                                await manager.loadWindows()
                                syncLocalSelections()
                            }
                        }
                    } else {
                        Picker("Window", selection: $selectedWindowID) {
                            Text("Select window").tag(nil as CGWindowID?)
                            ForEach(manager.availableWindows, id: \.windowID) { window in
                                Text(windowDisplayName(window))
                                    .tag(window.windowID as CGWindowID?)
                            }
                        }
                        .frame(width: 250)

                        Button("Refresh Windows") {
                            Task {
                                await manager.loadWindows()
                                syncLocalSelections()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if captureMode == .area {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Area")
                            .font(.headline)

                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                areaField("X", value: $areaX)
                                areaField("Y", value: $areaY)
                            }
                            GridRow {
                                areaField("W", value: $areaWidth)
                                areaField("H", value: $areaHeight)
                            }
                        }
                    }
                    .frame(width: 250, alignment: .leading)
                }

                Text("Target: \(manager.selectedTargetSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 250, alignment: .leading)

                if !manager.availableCameras.isEmpty {
                    Picker("Camera", selection: $manager.selectedCameraID) {
                        ForEach(manager.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera.uniqueID as String?)
                        }
                    }
                    .frame(width: 250)
                }

                if !manager.availableMicrophones.isEmpty {
                    Picker("Microphone", selection: $manager.selectedMicrophoneID) {
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

            HStack(spacing: 16) {
                Button(action: { Task { await toggleRecording() } }) {
                    ZStack {
                        Circle()
                            .fill((manager.isRecording || manager.isPaused) ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 72, height: 72)

                        if manager.isRecording || manager.isPaused {
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

                if manager.isRecording || manager.isPaused {
                    Button(action: { togglePause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 52, height: 52)

                            Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

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

    private func syncLocalSelections() {
        selectedDisplay = manager.selectedDisplay
        captureMode = manager.captureMode
        selectedWindowID = manager.selectedWindowID
        areaX = manager.selectedAreaRect.origin.x
        areaY = manager.selectedAreaRect.origin.y
        areaWidth = manager.selectedAreaRect.width
        areaHeight = manager.selectedAreaRect.height
    }

    private func syncAreaSelection() {
        manager.selectedAreaRect = CGRect(
            x: areaX,
            y: areaY,
            width: max(areaWidth, 0),
            height: max(areaHeight, 0)
        )
    }

    private func areaField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
        }
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
        if manager.isRecording || manager.isPaused {
            await manager.stopRecording()
        } else {
            guard let target = manager.currentRecordingTarget() else { return }
            await manager.startRecording(target: target)
        }
    }

    private func togglePause() {
        if manager.isPaused {
            manager.resumeRecording()
        } else {
            manager.pauseRecording()
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

                Section("Transcription") {
                    SecureField("Groq API Key", text: $formData.groqAPIKey)
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
