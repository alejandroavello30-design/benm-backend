import SwiftUI
import UniformTypeIdentifiers

struct AttendanceRecord: Decodable, Identifiable {
    let name: String
    let date: String
    let markedAt: String
    let markedBy: String
    let source: String
    var id: String { date + "|" + name }
}
struct AttendanceReply: Decodable { let date: String; let today: String; let role: String; let records: [AttendanceRecord] }
struct AttendanceMark: Decodable { let duplicate: Bool }

extension BENMAPI {
    func attendance(token: String, date: String = "") async throws -> AttendanceReply {
        var request = URLRequest(url: url("attendance", query: date.isEmpty ? [:] : ["date": date]))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try JSONDecoder().decode(AttendanceReply.self, from: await checked(request))
    }
    func markAttendance(token: String, name: String, date: String) async throws -> AttendanceMark {
        var request = URLRequest(url: url("attendance"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["name": name, "date": date])
        return try JSONDecoder().decode(AttendanceMark.self, from: await checked(request))
    }
}

struct AttendanceView: View {
    @ObservedObject var radio: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var records: [AttendanceRecord] = []
    @State private var date = ""
    @State private var today = ""
    @State private var selectedDate = Date()
    @State private var member = ""
    @State private var busy = false
    @State private var message: String?
    @State private var export = false
    @State private var document = ExportDocument(data: Data())
    private var admin: Bool { radio.role == "admin" }
    private func day(_ value: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "America/Santiago")
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: value)
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Registrar asistencia") {
                    Text("Día: \(date.isEmpty ? "Cargando…" : date)")
                    if admin {
                        DatePicker("Fecha", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .onChange(of: selectedDate) { value in Task { await load(day(value)) } }
                        TextField("Nombre del integrante", text: $member)
                    } else { Text(radio.name) }
                    Button("Marcar asistencia") { Task { await mark() } }
                        .disabled(busy || date.isEmpty || (!admin && date != today))
                    if busy { ProgressView() }
                }
                Section("Asistencia del equipo · \(records.count)") {
                    if records.isEmpty { Text("Sin registros para este día.").foregroundStyle(.secondary) }
                    ForEach(records) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text("\(item.markedAt) · Registró: \(item.markedBy)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Actualizar") { Task { await load(date) } }.disabled(busy)
                Button("Exportar asistencia a Excel") { exportRecords() }.disabled(busy || date.isEmpty)
            }
            .navigationTitle("Asistencia")
            .toolbar { Button("Cerrar") { dismiss() } }
            .task { member = radio.name; await load() }
            .refreshable { await load(date) }
            .alert("Asistencia", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Aceptar") { message = nil }
            } message: { Text(message ?? "") }
            .fileExporter(isPresented: $export, document: document, contentType: .commaSeparatedText, defaultFilename: "BENM-asistencia-\(date).csv") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
        }
    }
    private func load(_ requested: String = "") async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard !radio.attendanceToken.isEmpty else { message = "Vuelve a conectar para habilitar la asistencia."; return }
        do {
            let reply = try await radio.api.attendance(token: radio.attendanceToken, date: requested)
            records = reply.records; date = reply.date; today = reply.today
        } catch { message = error.localizedDescription }
    }
    private func mark() async {
        guard !busy else { return }
        let name = (admin ? member : radio.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { message = "Ingresa un nombre de hasta 30 caracteres."; return }
        busy = true
        do {
            let reply = try await radio.api.markAttendance(token: radio.attendanceToken, name: name, date: admin ? date : today)
            message = reply.duplicate ? "La asistencia ya estaba registrada. Se conservó la primera hora." : "Asistencia registrada."
        } catch { message = error.localizedDescription }
        busy = false
        await load(date)
    }
    private func exportRecords() {
        func field(_ value: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let lines = [["Nombre", "Fecha", "Hora de registro", "Registrado por", "Origen"]] + records.map { [$0.name, $0.date, $0.markedAt, $0.markedBy, $0.source] }
        document = ExportDocument(data: Data(("\u{FEFF}" + lines.map { $0.map(field).joined(separator: ";") }.joined(separator: "\r\n")).utf8))
        export = true
    }
}
