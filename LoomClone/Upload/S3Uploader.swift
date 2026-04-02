import Foundation
import AWSS3
import AWSClientRuntime
import Smithy
import SmithyHTTPAPI
import SmithyIdentity

struct AWSSettingsFormData {
    var accessKeyId: String = ""
    var secretAccessKey: String = ""
    var sessionToken: String = ""
    var region: String = "us-east-1"
    var bucket: String = ""
    var usePublicURLs: Bool = false
    var publicBaseURL: String = ""
    var presignedURLExpiration: String = "3600"
}

enum AWSSettingsStorage {
    private static let accessKeyIdKey = "aws.accessKeyId"
    private static let secretAccessKeyKey = "aws.secretAccessKey"
    private static let sessionTokenKey = "aws.sessionToken"
    private static let regionKey = "aws.region"
    private static let bucketKey = "aws.bucket"
    private static let usePublicURLsKey = "aws.usePublicURLs"
    private static let publicBaseURLKey = "aws.publicBaseURL"
    private static let presignedURLExpirationKey = "aws.presignedURLExpiration"

    static func load() -> AWSSettingsFormData {
        let defaults = UserDefaults.standard
        return AWSSettingsFormData(
            accessKeyId: defaults.string(forKey: accessKeyIdKey) ?? "",
            secretAccessKey: defaults.string(forKey: secretAccessKeyKey) ?? "",
            sessionToken: defaults.string(forKey: sessionTokenKey) ?? "",
            region: defaults.string(forKey: regionKey) ?? "us-east-1",
            bucket: defaults.string(forKey: bucketKey) ?? "",
            usePublicURLs: defaults.bool(forKey: usePublicURLsKey),
            publicBaseURL: defaults.string(forKey: publicBaseURLKey) ?? "",
            presignedURLExpiration: defaults.string(forKey: presignedURLExpirationKey) ?? "3600"
        )
    }

    static func save(_ formData: AWSSettingsFormData) {
        let defaults = UserDefaults.standard
        defaults.set(formData.accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines), forKey: accessKeyIdKey)
        defaults.set(formData.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: secretAccessKeyKey)
        defaults.set(formData.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: sessionTokenKey)
        defaults.set(formData.region.trimmingCharacters(in: .whitespacesAndNewlines), forKey: regionKey)
        defaults.set(formData.bucket.trimmingCharacters(in: .whitespacesAndNewlines), forKey: bucketKey)
        defaults.set(formData.usePublicURLs, forKey: usePublicURLsKey)
        defaults.set(formData.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: publicBaseURLKey)
        defaults.set(formData.presignedURLExpiration.trimmingCharacters(in: .whitespacesAndNewlines), forKey: presignedURLExpirationKey)
    }
}

class S3Uploader: @unchecked Sendable {
    enum DownloadURLMode {
        case presigned
        case publicURL(baseURL: String?)
    }

    struct Config {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String?
        let region: String
        let bucket: String
        let downloadURLMode: DownloadURLMode
        let presignedURLExpiration: TimeInterval

        static func load() throws -> Config {
            let storedSettings = AWSSettingsStorage.load()
            let environment = ProcessInfo.processInfo.environment

            let accessKey = firstNonEmptyValue(
                storedSettings.accessKeyId,
                environment["AWS_ACCESS_KEY_ID"]
            )
            let secretKey = firstNonEmptyValue(
                storedSettings.secretAccessKey,
                environment["AWS_SECRET_ACCESS_KEY"]
            )
            let sessionToken = firstNonEmptyValue(
                storedSettings.sessionToken,
                environment["AWS_SESSION_TOKEN"]
            )

            guard let accessKey, let secretKey else {
                throw S3Error.missingCredentials
            }

            let region = firstNonEmptyValue(storedSettings.region, environment["AWS_REGION"]) ?? "us-east-1"

            guard let bucket = firstNonEmptyValue(storedSettings.bucket, environment["S3_BUCKET"]) else {
                throw S3Error.missingBucket
            }

            let urlMode = firstNonEmptyValue(
                storedSettings.usePublicURLs ? "public" : nil,
                environment["S3_DOWNLOAD_URL_MODE"]?.lowercased()
            )
            let downloadURLMode: DownloadURLMode
            if urlMode == "public" {
                downloadURLMode = .publicURL(
                    baseURL: firstNonEmptyValue(
                        storedSettings.publicBaseURL,
                        environment["S3_PUBLIC_BASE_URL"]
                    )
                )
            } else {
                downloadURLMode = .presigned
            }

            let expiration = firstNonEmptyValue(
                storedSettings.presignedURLExpiration,
                environment["S3_PRESIGNED_URL_EXPIRATION"]
            ).flatMap(TimeInterval.init) ?? 3600

            return Config(
                accessKeyId: accessKey,
                secretAccessKey: secretKey,
                sessionToken: sessionToken,
                region: region,
                bucket: bucket,
                downloadURLMode: downloadURLMode,
                presignedURLExpiration: expiration
            )
        }
    }

    func upload(fileURL: URL, progressHandler: @escaping (Double) -> Void) async throws -> String {
        let config = try Config.load()

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent

        let s3Config = try await S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: StaticAWSCredentialIdentityResolver(
                .init(
                    accessKey: config.accessKeyId,
                    secret: config.secretAccessKey,
                    sessionToken: config.sessionToken
                )
            ),
            region: config.region
        )

        let client = S3Client(config: s3Config)
        let key = "recordings/\(fileName)"

        let input = PutObjectInput(
            body: .data(fileData),
            bucket: config.bucket,
            contentType: "video/mp4",
            key: key
        )

        // Note: progress tracking is approximate for PoC
        progressHandler(0.1)
        do {
            _ = try await client.putObject(input: input)
        } catch {
            throw S3Error.serviceFailure(Self.describe(error: error))
        }

        progressHandler(1.0)

        do {
            return try await makeDownloadURL(client: client, config: config, key: key)
        } catch {
            throw S3Error.serviceFailure(Self.describe(error: error))
        }
    }

    private func makeDownloadURL(client: S3Client, config: Config, key: String) async throws -> String {
        switch config.downloadURLMode {
        case .presigned:
            let request = try await client.presignedRequestForGetObject(
                input: GetObjectInput(
                    bucket: config.bucket,
                    key: key
                ),
                expiration: config.presignedURLExpiration
            )

            guard let url = request.url else {
                throw S3Error.failedToGenerateDownloadURL
            }

            return url.absoluteString
        case .publicURL(let baseURL):
            if let baseURL, !baseURL.isEmpty {
                return "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(key)"
            }

            return "https://\(config.bucket).s3.\(config.region).amazonaws.com/\(key)"
        }
    }

    private static func describe(error: Error) -> String {
        let reflected = String(reflecting: error)
        if reflected.contains("UnknownAWSHTTPServiceError") {
            return "S3 rejected the request. Check the bucket region, bucket name, IAM permissions, and confirm the bucket policy allows reads for recordings when public URLs are enabled."
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty, message != "The operation couldn’t be completed." {
            return message
        }

        return reflected
    }
}

private func firstNonEmptyValue(_ candidates: String?...) -> String? {
    for candidate in candidates {
        if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

enum S3Error: LocalizedError {
    case missingCredentials
    case missingBucket
    case failedToGenerateDownloadURL
    case serviceFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing AWS credentials. Add them in Settings or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
        case .missingBucket:
            return "Missing S3 bucket. Add it in Settings or set S3_BUCKET."
        case .failedToGenerateDownloadURL:
            return "Upload succeeded, but the app could not generate a download URL"
        case .serviceFailure(let message):
            return message
        }
    }
}
