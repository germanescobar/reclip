import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case s3
        case groq
        case done
    }

    @Bindable var manager: RecordingManager
    var onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var formData: AWSSettingsFormData = AWSSettingsStorage.load()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 16)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)

            Divider()

            footer
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
        }
        .frame(width: 560, height: 640)
        .task {
            await manager.refreshPermissionStatusAsync()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Reclip")
                .font(.title.bold())
            Text(stepTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionsStep
        case .s3:
            s3Step
        case .groq:
            groqStep
        case .done:
            doneStep
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") {
                    goBack()
                }
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if step == .groq {
                Button("Skip for now") {
                    formData.groqAPIKey = ""
                    AWSSettingsStorage.save(formData)
                    advance()
                }
            }

            Button(primaryButtonTitle) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!primaryActionEnabled)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let's get you set up")
                .font(.title2.bold())

            Text("Reclip records your screen, camera, and microphone, uploads the recording to your own S3 bucket, and (optionally) transcribes it with Groq.")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("This quick setup will:")
                .font(.headline)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                bullet(symbol: "lock.shield", title: "Grant macOS permissions", subtitle: "Camera, microphone, and screen recording.")
                bullet(symbol: "externaldrive.connected.to.line.below", title: "Configure your S3 bucket", subtitle: "Where recordings will be uploaded.")
                bullet(symbol: "waveform", title: "Add a Groq API key (optional)", subtitle: "For automatic transcription.")
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant permissions")
                .font(.title2.bold())

            Text("Reclip needs these macOS permissions to record. Grant them in order.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Camera and microphone",
                    isComplete: manager.cameraPermissionGranted && manager.microphonePermissionGranted,
                    description: "Used for the floating camera bubble and audio capture."
                )

                if !(manager.cameraPermissionGranted && manager.microphonePermissionGranted) {
                    Button("Allow Camera and Microphone") {
                        Task {
                            await manager.requestCameraAndMicrophonePermissions()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Screen recording",
                    isComplete: manager.screenPermissionGranted && !manager.needsAppRestart,
                    description: "Required to capture your display."
                )

                if manager.canRequestScreenPermission && !manager.screenPermissionGranted {
                    HStack {
                        Button("Request Screen Recording Access") {
                            Task {
                                await manager.beginScreenRecordingPermissionFlow()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open System Settings") {
                            manager.openScreenRecordingSettings()
                        }
                    }
                }

                if manager.needsAppRestart {
                    Text("macOS applies screen recording access after Reclip quits. Turn it on in System Settings, then reopen Reclip — onboarding will resume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Quit and Reopen Reclip") {
                        manager.quitApplication()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("Refresh Status") {
                Task {
                    await manager.refreshPermissionStatusAsync()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var s3Step: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure your S3 bucket")
                    .font(.title2.bold())

                Text("Recordings are uploaded to an S3 bucket you control. Enter credentials with PutObject access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Form {
                    Section("Credentials") {
                        TextField("Access Key ID", text: $formData.accessKeyId)
                        SecureField("Secret Access Key", text: $formData.secretAccessKey)
                        SecureField("Session Token (optional)", text: $formData.sessionToken)
                    }

                    Section("Bucket") {
                        TextField("Region", text: $formData.region, prompt: Text("us-east-1"))
                        TextField("Bucket Name", text: $formData.bucket)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var groqStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Groq API key")
                .font(.title2.bold())

            Text("Groq powers automatic transcription of your recordings. This step is optional — you can skip and add a key later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                Section("Groq") {
                    SecureField("Groq API Key", text: $formData.groqAPIKey)
                }
            }
            .formStyle(.grouped)

            Link("Get a Groq API key", destination: URL(string: "https://console.groq.com/keys")!)
                .font(.callout)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.title2.bold())
            Text("Reclip is ready to record. Click the menu bar icon any time to start a new recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func bullet(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(title: String, isComplete: Bool, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome:    return "Step 1 of 5 — Welcome"
        case .permissions: return "Step 2 of 5 — Permissions"
        case .s3:         return "Step 3 of 5 — S3 Bucket"
        case .groq:       return "Step 4 of 5 — Transcription"
        case .done:       return "Step 5 of 5 — All set"
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .permissions: return "Continue"
        case .s3: return "Save & Continue"
        case .groq: return "Save & Continue"
        case .done: return "Start Using Reclip"
        }
    }

    private var primaryActionEnabled: Bool {
        switch step {
        case .welcome, .done:
            return true
        case .permissions:
            return manager.permissionsReady
        case .s3:
            return !trimmed(formData.accessKeyId).isEmpty
                && !trimmed(formData.secretAccessKey).isEmpty
                && !trimmed(formData.region).isEmpty
                && !trimmed(formData.bucket).isEmpty
        case .groq:
            return true
        }
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func primaryAction() {
        switch step {
        case .welcome, .permissions:
            advance()
        case .s3:
            AWSSettingsStorage.save(formData)
            advance()
        case .groq:
            AWSSettingsStorage.save(formData)
            advance()
        case .done:
            OnboardingState.markCompleted()
            onComplete()
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }
}
