import Foundation

/// The wire format of the `tatami` command: one JSON object per line over a local socket. A request is checked
/// completely before anything is acted on; a reply carries success or a message.
public enum CLIProtocol {
    public static let version = 1
    public static let maxRequestBytes = 64 * 1024
    public static let maxResponseBytes = 1024 * 1024
    public static let maxArguments = 16
    public static let maxArgumentBytes = 256
}

public enum CLIRequestError: Error, Equatable {
    case malformed, tooLarge, unsupportedVersion(Int)
}

public struct CLIRequest: Codable, Equatable, Sendable {
    public var version: Int
    public var args: [String]
    public init(args: [String], version: Int = CLIProtocol.version) { self.args = args; self.version = version }

    private struct VersionOnly: Decodable { var version: Int }

    /// Reads one request line. A newer client is refused by version, whatever else it sent.
    public static func decode(_ data: Data) -> Result<CLIRequest, CLIRequestError> {
        guard data.count <= CLIProtocol.maxRequestBytes else { return .failure(.tooLarge) }
        guard let request = try? JSONDecoder().decode(CLIRequest.self, from: data) else {
            if let other = try? JSONDecoder().decode(VersionOnly.self, from: data), other.version != CLIProtocol.version {
                return .failure(.unsupportedVersion(other.version))
            }
            return .failure(.malformed)
        }
        guard request.version == CLIProtocol.version else { return .failure(.unsupportedVersion(request.version)) }
        guard request.args.count <= CLIProtocol.maxArguments, request.args.allSatisfy({ $0.utf8.count <= CLIProtocol.maxArgumentBytes }) else {
            return .failure(.tooLarge)
        }
        return .success(request)
    }
}

public struct CLIResponse: Codable, Equatable, Sendable {
    public var version: Int
    public var ok: Bool
    public var output: String
    public var error: String?

    public static func success(_ output: String = "") -> CLIResponse { CLIResponse(version: CLIProtocol.version, ok: true, output: output, error: nil) }
    public static func failure(_ message: String) -> CLIResponse { CLIResponse(version: CLIProtocol.version, ok: false, output: "", error: message) }
}

public enum CLICodec {
    /// Compact JSON with sorted keys and a trailing newline: one document per line.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    public static func decodeResponse(_ data: Data) throws -> CLIResponse { try JSONDecoder().decode(CLIResponse.self, from: data) }
}

public enum CLIPaths {
    /// A Unix socket path must fit in about 104 bytes; stay safely under it.
    public static let maxSocketPathBytes = 100

    /// Inside the user's own Application Support folder, or a short private folder when the home path is too long.
    public static func socketPath(home: String, uid: UInt32) -> String {
        let preferred = home + "/Library/Application Support/Tatami/tatami.sock"
        return preferred.utf8.count <= maxSocketPathBytes ? preferred : "/tmp/tatami-\(uid)/tatami.sock"
    }
}
