import Foundation
import AVFoundation

struct TranscriptSegment: Codable, Equatable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

struct RecordingTranscript: Codable, Equatable {
    let text: String
    let segments: [TranscriptSegment]
}

enum GroqTranscriptionError: LocalizedError {
    case missingAPIKey
    case unsupportedFile
    case missingAudioTrack
    case exportFailed(String)
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key missing. Add it in Settings or set GROQ_API_KEY."
        case .unsupportedFile:
            return "The recording file could not be prepared for transcription."
        case .missingAudioTrack:
            return "No audio track was found in the recording."
        case .exportFailed(let message):
            return "Failed to prepare audio for transcription: \(message)"
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "Groq returned an unexpected response."
        }
    }
}

private struct GroqVerboseTranscriptionResponse: Decodable {
    struct Segment: Decodable {
        let id: Int?
        let start: Double
        let end: Double
        let text: String
    }

    let text: String
    let segments: [Segment]?
}

private struct TranscriptionChunk {
    let fileURL: URL
    let startTime: Double
}

final class GroqTranscriptionClient {
    private let session: URLSession

    private let transcriptionURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3-turbo"
    private let maxDirectFileSizeBytes = 80 * 1024 * 1024
    private let chunkDuration: Double = 30
    private let overlapDuration: Double = 2

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribeIfPossible(fileURL: URL) async -> RecordingTranscript? {
        do {
            return try await transcribe(fileURL: fileURL)
        } catch {
            print("[Transcription] Skipping transcript: \(error.localizedDescription)")
            return nil
        }
    }

    private func transcribe(fileURL: URL) async throws -> RecordingTranscript {
        let apiKey = try loadAPIKey()
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

        if fileSize < maxDirectFileSizeBytes {
            let response = try await transcribeFile(fileURL: fileURL, apiKey: apiKey)
            return normalizeTranscript(from: response)
        }

        let preparedAudioURL = try await exportAudioForTranscription(from: fileURL)
        defer { try? FileManager.default.removeItem(at: preparedAudioURL) }

        let chunks = try await createChunks(from: preparedAudioURL)
        defer {
            for chunk in chunks {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
        }

        let responses = try await transcribeChunks(chunks, apiKey: apiKey)
        return mergeChunkResponses(responses)
    }

    private func loadAPIKey() throws -> String {
        let settings = AWSSettingsStorage.load()
        let apiKey = firstNonEmptyValue(
            settings.groqAPIKey,
            ProcessInfo.processInfo.environment["GROQ_API_KEY"]
        )

        guard let apiKey else {
            throw GroqTranscriptionError.missingAPIKey
        }

        return apiKey
    }

    private func transcribeChunks(_ chunks: [TranscriptionChunk], apiKey: String) async throws -> [(Double, GroqVerboseTranscriptionResponse)] {
        var responses: [(Double, GroqVerboseTranscriptionResponse)] = []
        responses.reserveCapacity(chunks.count)

        for chunk in chunks {
            let response = try await transcribeFile(fileURL: chunk.fileURL, apiKey: apiKey)
            responses.append((chunk.startTime, response))
        }

        return responses
    }

    private func transcribeFile(fileURL: URL, apiKey: String) async throws -> GroqVerboseTranscriptionResponse {
        let fileData = try Data(contentsOf: fileURL)
        let mimeType = mimeType(for: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: transcriptionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(named: "model", value: model, boundary: boundary, to: &body)
        appendFormField(named: "response_format", value: "verbose_json", boundary: boundary, to: &body)
        appendFormField(named: "timestamp_granularities[]", value: "segment", boundary: boundary, to: &body)
        appendFileField(
            named: "file",
            filename: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileData: fileData,
            boundary: boundary,
            to: &body
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqTranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Groq request failed with status \(httpResponse.statusCode)."
            throw GroqTranscriptionError.requestFailed(message)
        }

        do {
            return try JSONDecoder().decode(GroqVerboseTranscriptionResponse.self, from: data)
        } catch {
            throw GroqTranscriptionError.invalidResponse
        }
    }

    private func normalizeTranscript(from response: GroqVerboseTranscriptionResponse) -> RecordingTranscript {
        let segments = (response.segments ?? [])
            .enumerated()
            .compactMap { entry -> TranscriptSegment? in
                let (index, segment) = entry
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }

                return TranscriptSegment(
                    id: index,
                    start: segment.start,
                    end: segment.end,
                    text: text
                )
            }

        if !segments.isEmpty {
            let combinedText = segments.map(\.text).joined(separator: " ")
            return RecordingTranscript(text: combinedText, segments: segments)
        }

        return RecordingTranscript(
            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: []
        )
    }

    private func mergeChunkResponses(_ responses: [(Double, GroqVerboseTranscriptionResponse)]) -> RecordingTranscript {
        var mergedSegments: [TranscriptSegment] = []
        var nextID = 0
        var lastEnd: Double = 0
        var normalizedTexts = Set<String>()

        for (chunkStart, response) in responses {
            let segments = response.segments ?? []

            for segment in segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let absoluteStart = max(0, chunkStart + segment.start)
                let absoluteEnd = max(absoluteStart, chunkStart + segment.end)
                let normalizedText = normalizeText(text)

                if absoluteEnd <= lastEnd + 0.05 {
                    continue
                }

                if let lastSegment = mergedSegments.last,
                   absoluteStart < lastEnd,
                   normalizeText(lastSegment.text) == normalizedText {
                    continue
                }

                if normalizedTexts.contains("\(Int(absoluteStart * 10)):\(normalizedText)") {
                    continue
                }

                mergedSegments.append(
                    TranscriptSegment(
                        id: nextID,
                        start: absoluteStart,
                        end: absoluteEnd,
                        text: text
                    )
                )
                normalizedTexts.insert("\(Int(absoluteStart * 10)):\(normalizedText)")
                nextID += 1
                lastEnd = absoluteEnd
            }
        }

        let text = mergedSegments.map(\.text).joined(separator: " ")
        return RecordingTranscript(text: text, segments: mergedSegments)
    }

    private func createChunks(from audioURL: URL) async throws -> [TranscriptionChunk] {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard totalSeconds > 0 else {
            throw GroqTranscriptionError.unsupportedFile
        }

        var chunks: [TranscriptionChunk] = []
        var currentStart: Double = 0

        while currentStart < totalSeconds {
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("reclip-transcript-chunk-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let end = min(totalSeconds, currentStart + chunkDuration)
            let timeRange = CMTimeRange(
                start: CMTime(seconds: currentStart, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )

            try await exportChunk(from: asset, timeRange: timeRange, to: chunkURL)
            chunks.append(TranscriptionChunk(fileURL: chunkURL, startTime: currentStart))

            if end >= totalSeconds {
                break
            }

            currentStart = max(0, end - overlapDuration)
        }

        return chunks
    }

    private func exportAudioForTranscription(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            throw GroqTranscriptionError.missingAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reclip-transcript-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let reader = try AVAssetReader(asset: asset)

        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
        )

        writerInput.expectsMediaDataInRealTime = false

        guard reader.canAdd(readerOutput), writer.canAdd(writerInput) else {
            throw GroqTranscriptionError.unsupportedFile
        }

        reader.add(readerOutput)
        writer.add(writerInput)

        guard reader.startReading() else {
            throw GroqTranscriptionError.exportFailed(reader.error?.localizedDescription ?? "Reader failed to start.")
        }

        guard writer.startWriting() else {
            throw GroqTranscriptionError.exportFailed(writer.error?.localizedDescription ?? "Writer failed to start.")
        }

        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.reclip.groq-transcription.export")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        if !writerInput.append(sampleBuffer) {
                            reader.cancelReading()
                            writerInput.markAsFinished()
                            writer.cancelWriting()
                            continuation.resume(throwing: GroqTranscriptionError.exportFailed(writer.error?.localizedDescription ?? "Failed to append audio sample."))
                            return
                        }
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if let error = writer.error {
                                continuation.resume(throwing: GroqTranscriptionError.exportFailed(error.localizedDescription))
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                }
            }
        }

        return outputURL
    }

    private func exportChunk(from asset: AVURLAsset, timeRange: CMTimeRange, to outputURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw GroqTranscriptionError.exportFailed("Could not create audio export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange

        await exportSession.export()

        if exportSession.status != .completed {
            throw GroqTranscriptionError.exportFailed(exportSession.error?.localizedDescription ?? "Chunk export failed.")
        }
    }

    private func appendFormField(named name: String, value: String, boundary: String, to data: inout Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileField(named name: String, filename: String, mimeType: String, fileData: Data, boundary: String, to data: inout Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "mp4":
            return "video/mp4"
        case "m4a":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private func normalizeText(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
