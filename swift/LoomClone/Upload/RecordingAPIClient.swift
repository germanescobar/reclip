import Foundation

struct CreateRecordingResponse: Decodable {
    let success: Bool
    let recording: RecordingInfo
    let shareable_url: String

    struct RecordingInfo: Decodable {
        let id: String
        let short_id: String
        let title: String
        let description: String?
        let created_at: String
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum RecordingAPIError: LocalizedError {
    case missingConfig
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "API Base URL and API Key must be configured in Settings."
        case .requestFailed(let message):
            return message
        }
    }
}

class RecordingAPIClient {
    func createRecording(title: String, s3URL: String, description: String? = nil) async throws -> String {
        let settings = AWSSettingsStorage.load()

        guard !settings.apiBaseURL.isEmpty, !settings.apiKey.isEmpty else {
            throw RecordingAPIError.missingConfig
        }

        let baseURL = settings.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/api/recordings") else {
            throw RecordingAPIError.requestFailed("Invalid API base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "title": title,
            "s3_url": s3URL
        ]
        if let description, !description.isEmpty {
            body["description"] = description
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecordingAPIError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            let decoded = try JSONDecoder().decode(CreateRecordingResponse.self, from: data)
            return decoded.shareable_url
        }

        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            throw RecordingAPIError.requestFailed(errorResponse.error)
        }

        throw RecordingAPIError.requestFailed("API request failed with status \(httpResponse.statusCode)")
    }
}
