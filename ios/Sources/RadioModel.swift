import SwiftUI
import LiveKit
import AVFoundation
import AudioToolbox
import UserNotifications

@MainActor
final class RadioModel: NSObject, ObservableObject {
    @Published var name = UserDefaults.standard.string(forKey: "benm.name") ?? ""
    @Published var code = Credentials.read()
    @Published var attendanceToken = ""
    @Published var recoverPrompt = false
    @Published var channel: Channel = .general
    @Published var connected = false
    @Published var busy = false
    @Published var transmitting = false
    @Published var status = "Desconectado"
    @Published var users: [String] = []
    @Published var speaker = "Canal en escucha"
    @Published var error: String?
    @Published var alert: Emergency?
    @Published var role = "member"
    @Published var files: [TeamFile] = []
    @Published var filesBusy = false
    let room = Room()
    let api = BENMAPI()
    private var poll: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var wantsMicrophone = false
    private var seen = Set<String>()
    private var joinedAt: Double = 0
    private var lastPollFailed = false

    override init() {
        super.init()
        room.add(delegate: self)
    }

    func connect(to next: Channel? = nil, recover: Bool = false) async {
        guard !busy else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 30, !code.isEmpty else {
            error = "Ingresa tu nombre (hasta 30 caracteres) y el código del equipo."
            return
        }
        busy = true
        defer { busy = false }
        if connected { await disconnect() }
        if let next { channel = next }
        status = "Conectando…"
        do {
            // Establish baseline first, so a stale alert from a previous session is not replayed.
            if let baseline = try? await api.emergency(channel: channel), let previous = baseline.alert { seen.insert(previous.id) }
            let reply = try await api.token(name: cleanName, code: code, channel: channel, recover: recover)
            try await room.connect(url: reply.serverUrl, token: reply.participantToken)
            try await room.localParticipant.setMicrophone(enabled: false)
            name = cleanName
            role = reply.role
            attendanceToken = reply.attendanceToken ?? ""
            Credentials.save(code)
            connected = true
            joinedAt = Date().timeIntervalSince1970 * 1000
            status = "Conectado"
            UserDefaults.standard.set(cleanName, forKey: "benm.name")
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            poll = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.refreshRoom()
                    do {
                        let result = try await self.api.emergency(channel: self.channel)
                        guard !Task.isCancelled else { return }
                        self.lastPollFailed = false
                        if let alert = result.alert { self.receive(alert) }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.lastPollFailed = true
                    }
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                }
            }
        } catch {
            await room.disconnect()
            connected = false
            status = "Desconectado"
            if let service = error as? ServiceError, service.status == 409 { recoverPrompt = true }
            else { self.error = error.localizedDescription }
        }
    }

    func logout() async {
        await disconnect()
        name = ""; code = ""
        UserDefaults.standard.removeObject(forKey: "benm.name")
        Credentials.clear()
    }

    func disconnect() async {
        connected = false
        poll?.cancel()
        poll = nil
        wantsMicrophone = false
        transmitting = false
        // Wait for any in-flight enable before disconnecting, avoiding an enable after release.
        await microphoneTask?.value
        await room.disconnect()
        connected = false
        users = []
        speaker = "Canal en escucha"
        status = "Desconectado"
        alert = nil
        files = []
        attendanceToken = ""
        role = "member"
    }

    func setTalking(_ enabled: Bool) {
        wantsMicrophone = enabled && connected && !busy && room.connectionState == .connected
        guard microphoneTask == nil else { return }
        guard wantsMicrophone || transmitting else { return }
        microphoneTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                let desired = self.wantsMicrophone
                do {
                    try await self.room.localParticipant.setMicrophone(enabled: desired)
                    self.transmitting = desired
                } catch {
                    self.wantsMicrophone = false
                    self.transmitting = false
                    // Fail closed if publication fails partway through.
                    try? await self.room.localParticipant.setMicrophone(enabled: false)
                    await self.room.disconnect()
                    self.poll?.cancel()
                    self.connected = false
                    self.status = "Desconectado"
                    self.error = "No se pudo controlar el micrófono. Se desconectó la radio: \(error.localizedDescription)"
                    break
                }
            } while self.transmitting != self.wantsMicrophone
            self.microphoneTask = nil
        }
    }

    func refreshRoom() {
        guard connected else { return }
        if room.connectionState != .connected { setTalking(false) }
        if room.connectionState == .disconnected {
            connected = false
            status = "Conexión perdida. Vuelve a conectar."
            users = []
            poll?.cancel()
            return
        }
        status = room.connectionState == .connected ? (lastPollFailed ? "Radio conectada · consulta de alertas pendiente" : "Conectado") : "Reconectando…"
        let participants = Array(room.remoteParticipants.values)
        users = ([name] + participants.map { $0.name ?? "Integrante" }).sorted()
        let speaking = participants.filter { $0.isSpeaking }.map { $0.name ?? "Integrante" }
        speaker = transmitting ? "Tú estás transmitiendo" : (speaking.isEmpty ? "Canal en escucha" : speaking.joined(separator: ", "))
    }

    func receive(_ incoming: Emergency) {
        guard connected, !seen.contains(incoming.id) else { return }
        seen.insert(incoming.id)
        guard incoming.sender != name else { return }
        setTalking(false)
        alert = incoming
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let content = UNMutableNotificationContent()
        content.title = "BENM · \(incoming.sender)"
        content.body = incoming.message
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: incoming.id, content: content, trigger: nil))
    }

    func sendEmergency(type: String, location: String) async {
        guard connected, !busy else { return }
        busy = true
        setTalking(false)
        defer { busy = false }
        let message = type == "EVACUACIÓN PARCIAL" ? "\(type) | \(location)" : type
        do {
            let reply = try await api.sendEmergency(name: name, channel: channel, message: message)
            guard let sent = reply.alert else { throw ServiceError(message: "El servidor no confirmó la alerta.") }
            seen.insert(sent.id)
            let packet = EmergencyPacket(type: "emergency", id: sent.id, sender: name, emergencyType: type, message: message)
            do {
                try await room.localParticipant.publish(data: JSONEncoder().encode(packet), options: DataPublishOptions(topic: "emergency", reliable: true))
                status = "Alerta enviada: \(type)"
            } catch {
                self.error = "La alerta se guardó en el servidor, pero falló el envío inmediato por radio. Los equipos conectados podrán recibirla por consulta."
            }
        } catch { self.error = error.localizedDescription }
    }

    func loadFiles() async {
        guard !filesBusy else { return }
        filesBusy = true
        defer { filesBusy = false }
        do {
            let reply = try await api.files(code: code)
            files = reply.files
            role = reply.role
            attendanceToken = reply.attendanceToken ?? ""
            Credentials.save(code)
        } catch { self.error = error.localizedDescription }
    }
    func upload(_ url: URL) async {
        guard role == "admin", !filesBusy else { return }
        filesBusy = true
        do { try await api.upload(url, code: code) } catch { self.error = error.localizedDescription }
        filesBusy = false
        await loadFiles()
    }
    func delete(_ file: TeamFile) async {
        guard role == "admin", !filesBusy else { return }
        filesBusy = true
        do { try await api.delete(file, code: code) } catch { self.error = error.localizedDescription }
        filesBusy = false
        await loadFiles()
    }
}

extension RadioModel: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor [weak self] in self?.refreshRoom() }
    }
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.refreshRoom() }
    }
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.refreshRoom() }
    }
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        Task { @MainActor [weak self] in self?.refreshRoom() }
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        guard topic == "emergency", let packet = try? JSONDecoder().decode(EmergencyPacket.self, from: data), packet.type == "emergency" else { return }
        let incoming = Emergency(id: packet.id, sender: packet.sender, message: packet.message, timestamp: nil)
        Task { @MainActor [weak self] in self?.receive(incoming) }
    }
}
