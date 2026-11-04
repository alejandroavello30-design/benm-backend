import Foundation
import UniformTypeIdentifiers

enum Channel: String, CaseIterable, Identifiable {
    case general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        }
    }
}

struct TokenReply: Decodable {
    let serverUrl: String
    let attendanceToken: String?
    let participantToken: String
    let role: String
}
struct TeamFile: Decodable, Identifiable {
    let id: String
    let name: String
    let size: Int
}
struct FileReply: Decodable { let role: String; let files: [TeamFile] }
struct Emergency: Decodable, Identifiable {
    let id: String
    let sender: String
    let message: String
    let timestamp: Double?
}
struct EmergencyReply: Decodable { let alert: Emergency? }
struct EmergencyPacket: Codable {
    let type: String
    let id: String
    let sender: String
    let emergencyType: String
    let message: String
}
struct ServiceError: LocalizedError {
    let message: String
    var status: Int = 0
    var errorDescription: String? { message }
}

struct BENMAPI {
    // Public service URL from the supplied Android project. No server secrets in the app.
    let base = URL(string: "https://benm-backend.onrender.com")!
    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceError(message: "Respuesta de servidor inválida.") }
        guard (200...299).contains(response.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ServiceError(message: (body?["error"] as? String) ?? "Error del servidor (\(response.statusCode)).", status: response.statusCode)
        }
        return data
    }
    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var request = URLRequest(url: url(path, query: query))
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try JSONDecoder().decode(T.self, from: await checked(request))
    }
    func token(name: String, code: String, channel: Channel, recover: Bool = false) async throws -> TokenReply {
        try await get("token", query: ["name": name, "accessCode": code, "room": channel.rawValue, "recoverSession": recover ? "true" : "false"])
    }
    func emergency(channel: Channel) async throws -> EmergencyReply {
        try await get("emergency", query: ["room": channel.rawValue])
    }
    func sendEmergency(name: String, channel: Channel, message: String) async throws -> EmergencyReply {
        var request = URLRequest(url: url("emergency"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["sender": name, "room": channel.rawValue, "message": message])
        return try JSONDecoder().decode(EmergencyReply.self, from: await checked(request))
    }
    func files(code: String) async throws -> FileReply {
        try await get("files", query: ["accessCode": code])
    }
    func download(_ file: TeamFile, code: String) async throws -> URL {
        let data = try await checked(URLRequest(url: url("files/\(file.id)", query: ["accessCode": code])))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: file.name).lastPathComponent
        let target = directory.appendingPathComponent(safeName.isEmpty ? "archivo" : safeName)
        try data.write(to: target, options: .atomic)
        return target
    }
    func delete(_ file: TeamFile, code: String) async throws {
        var request = URLRequest(url: url("files/\(file.id)", query: ["accessCode": code]))
        request.httpMethod = "DELETE"
        _ = try await checked(request)
    }
    func upload(_ file: URL, code: String) async throws {
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10 * 1024 * 1024 else { throw ServiceError(message: "El archivo supera el límite de 10 MB.") }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 10 * 1024 * 1024 else { throw ServiceError(message: "El archivo supera el límite de 10 MB.") }
        let boundary = "BENM-\(UUID().uuidString)"
        let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"accessCode\"\r\n\r\n\(code)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(bytes)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: url("files"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await checked(request)
    }
}
