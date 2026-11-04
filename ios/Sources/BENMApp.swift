import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UIKit

@main
struct BENMApp: App {
    @StateObject private var radio = RadioModel()
    var body: some Scene { WindowGroup { RadioView(radio: radio).preferredColorScheme(.dark) } }
}

private let navy = Color(red: 7/255, green: 17/255, blue: 31/255)
private let surface = Color(red: 13/255, green: 27/255, blue: 44/255)
private let cyan = Color(red: 36/255, green: 215/255, blue: 1)

struct RadioView: View {
    @ObservedObject var radio: RadioModel
    @Environment(\.scenePhase) private var phase
    @State private var showFiles = false
    @State private var showEmergency = false
    @State private var holding = false
    @State private var showRoster = false
    @State private var showAttendance = false
    @State private var exitAction: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BENM").font(.system(size: 34, weight: .black, design: .rounded))
                            Text("RADIO EQUIPO").font(.caption.bold()).tracking(3).foregroundStyle(cyan)
                        }
                        Spacer()
                        Image(systemName: radio.connected ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                            .font(.title2).foregroundStyle(radio.connected ? .green : .secondary)
                    }
                    Text(radio.status).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(radio.connected ? cyan : .gray).accessibilityLabel("Estado: \(radio.status)")

                    if radio.connected { console } else { login }
                    if radio.busy { ProgressView().tint(cyan) }
                    Text("iPhone · prueba 0.3.21. Las alertas requieren que BENM mantenga conexión; no se reciben con cierre forzado.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(navy.ignoresSafeArea()).tint(cyan)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showRoster) { RosterView() }
            .sheet(isPresented: $showAttendance) { AttendanceView(radio: radio) }
            .confirmationDialog("¿Estás seguro de \(exitAction == "logout" ? "salir y cambiar de usuario" : "desconectar")?", isPresented: Binding(get: { exitAction != nil }, set: { if !$0 { exitAction = nil } }), titleVisibility: .visible) {
                Button("Confirmar", role: .destructive) {
                    let logout = exitAction == "logout"
                    exitAction = nil
                    Task { if logout { await radio.logout() } else { await radio.disconnect() } }
                }
                Button("Cancelar", role: .cancel) { exitAction = nil }
            }
            .confirmationDialog("Tu nombre ya está conectado. ¿Recuperar la sesión en este iPhone?", isPresented: $radio.recoverPrompt, titleVisibility: .visible) {
                Button("Recuperar sesión") { Task { await radio.connect(recover: true) } }
                Button("Cancelar", role: .cancel) {}
            }
            .sheet(isPresented: $showFiles) { FilesView(radio: radio) }
            .sheet(isPresented: $showEmergency) { EmergencyComposer(radio: radio) }
            .fullScreenCover(item: $radio.alert) { alert in
                ZStack {
                    Color(red: 0.55, green: 0.02, blue: 0.08).ignoresSafeArea()
                    VStack(spacing: 30) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 74))
                        Text("ALERTA BENM").font(.largeTitle.bold())
                        Text(alert.message).font(.title.bold()).multilineTextAlignment(.center)
                        Text("Enviada por \(alert.sender)").font(.headline)
                        Button("ENTENDIDO") { radio.alert = nil }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    }.padding(30)
                }.interactiveDismissDisabled()
            }
            .alert("BENM", isPresented: Binding(get: { radio.error != nil }, set: { if !$0 { radio.error = nil } })) {
                Button("Aceptar") { radio.error = nil }
            } message: { Text(radio.error ?? "") }
            .onChange(of: phase) { value in
                if value != .active { holding = false; radio.setTalking(false) }
            }
            .onChange(of: radio.connected) { _ in holding = false }
            .onDisappear { radio.setTalking(false) }
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Conecta con tu equipo").font(.title2.bold())
            Text("Usa el mismo código de acceso de BENM Android.").font(.subheadline).foregroundStyle(.secondary)
            TextField("Tu nombre", text: $radio.name).textContentType(.name).textInputAutocapitalization(.words)
                .padding().background(navy, in: RoundedRectangle(cornerRadius: 12))
            SecureField("Código del equipo", text: $radio.code).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding().background(navy, in: RoundedRectangle(cornerRadius: 12))
            Picker("Canal", selection: $radio.channel) {
                ForEach(Channel.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            Button { Task { await radio.connect() } } label: {
                Label("CONECTAR", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).disabled(radio.busy)
            Button("Salir / Cambiar usuario") { exitAction = "logout" }.disabled(radio.busy)
        }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 22)).disabled(radio.busy)
    }

    private var console: some View {
        VStack(spacing: 20) {
            HStack {
                Text("General").font(.headline).frame(maxWidth: .infinity)
                Button("Lista") { radio.setTalking(false); showRoster = true }.frame(maxWidth: .infinity)
                Button("Asistencia") { radio.setTalking(false); showAttendance = true }.frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).disabled(radio.busy)
            Button { radio.setTalking(false); showFiles = true } label: {
                Label("INSTRUCTIVOS Y ARCHIVOS", systemImage: "books.vertical.fill").font(.subheadline.bold())
                    .frame(maxWidth: .infinity).padding(17).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }.disabled(radio.busy)
            VStack(spacing: 10) {
                Text(radio.channel.title.uppercased()).font(.caption.bold()).tracking(3).foregroundStyle(cyan)
                Text(radio.speaker).font(.headline).multilineTextAlignment(.center)
                ZStack {
                    Circle().stroke(cyan.opacity(0.12), lineWidth: 16)
                    Circle().fill(radio.transmitting ? Color.green : Color.blue)
                    VStack(spacing: 12) {
                        Image(systemName: radio.transmitting ? "waveform" : "mic.fill").font(.system(size: 56))
                        Text(radio.transmitting ? "TRANSMITIENDO" : "MANTÉN PARA HABLAR").font(.caption.bold())
                    }.foregroundStyle(.white)
                }
                .frame(width: 240, height: 240).padding(12)
                .contentShape(Circle())
                .accessibilityHidden(true)
                .overlay {
                    TalkControl(active: radio.transmitting) { pressed in radio.setTalking(pressed) }
                        .clipShape(Circle())
                }
                Text("Suelta para escuchar").font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("EQUIPO · \(radio.users.count)").font(.caption.bold()).foregroundStyle(cyan)
                Text(radio.users.joined(separator: " · ")).font(.subheadline)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(surface, in: RoundedRectangle(cornerRadius: 14))
            Button {
                holding = false
                radio.setTalking(false)
                showEmergency = true
            } label: {
                Label("ENVIAR ALERTA", systemImage: "exclamationmark.triangle.fill").font(.headline).frame(maxWidth: .infinity).padding(12)
            }.buttonStyle(.borderedProminent).tint(.red).disabled(radio.busy)
            Button("Desconectar") {
                radio.setTalking(false); exitAction = "disconnect"
            }.foregroundStyle(.secondary).disabled(radio.busy)
            Button("Salir / Cambiar usuario") { radio.setTalking(false); exitAction = "logout" }.disabled(radio.busy)
        }
    }
}

// UIKit tracking supplies cancellation when a scroll view or system gesture takes over.
// VoiceOver activation toggles transmission; leaving the app always releases it.
private struct TalkControl: UIViewRepresentable {
    var active: Bool
    var changed: (Bool) -> Void
    func makeUIView(context: Context) -> HoldControl {
        let control = HoldControl()
        control.backgroundColor = .clear
        control.isAccessibilityElement = true
        control.accessibilityLabel = "Micrófono"
        control.accessibilityTraits = .button
        control.changed = changed
        return control
    }
    func updateUIView(_ view: HoldControl, context: Context) {
        view.changed = changed
        view.active = active
        view.accessibilityValue = active ? "Transmitiendo. Activa para detener." : "Apagado. Activa para transmitir."
    }
    static func dismantleUIView(_ uiView: HoldControl, coordinator: ()) { uiView.changed?(false) }
}

private final class HoldControl: UIControl {
    var changed: ((Bool) -> Void)?
    var active = false
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { changed?(true); return true }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.contains(touch.location(in: self)) { changed?(false); return false }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { changed?(false) }
    override func cancelTracking(with event: UIEvent?) { changed?(false) }
    override func accessibilityActivate() -> Bool { changed?(!active); return true }
}

struct EmergencyComposer: View {
    @ObservedObject var radio: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var type = "ALPHA 1"
    @State private var location = ""
    @State private var confirm = false
    let types = ["ALPHA 1", "ALPHA 2", "SISMO", "BETA", "CÓDIGO G", "INUNDACIÓN", "EVACUACIÓN", "EVACUACIÓN PARCIAL"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Canal: \(radio.channel.title)") {
                    Picker("Tipo de alerta", selection: $type) { ForEach(types, id: \.self) { Text($0) } }
                    if type == "EVACUACIÓN PARCIAL" {
                        TextField("Lugar de la evacuación", text: $location).onChange(of: location) { location = String($0.prefix(120)) }
                    }
                }
                Button("Enviar alerta al canal", role: .destructive) { confirm = true }
                    .disabled(radio.busy || (type == "EVACUACIÓN PARCIAL" && location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }.navigationTitle("Alerta de emergencia")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
                .confirmationDialog("¿Enviar \(type) a \(radio.channel.title)?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Enviar alerta", role: .destructive) {
                        let selected = type
                        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                        Task { await radio.sendEmergency(type: selected, location: place) }
                    }
                }
        }
    }
}

struct FilesView: View {
    @ObservedObject var radio: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var preview: URL?
    @State private var downloading = false
    @State private var pendingDelete: TeamFile?
    var body: some View {
        NavigationStack {
            List {
                if radio.filesBusy || downloading { ProgressView() }
                if radio.files.isEmpty && !radio.filesBusy { Text("No hay instructivos disponibles.").foregroundStyle(.secondary) }
                ForEach(radio.files) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(file.name).font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Abrir") {
                                downloading = true
                                Task {
                                    defer { downloading = false }
                                    do { preview = try await radio.api.download(file, code: radio.code) }
                                    catch { radio.error = error.localizedDescription; dismiss() }
                                }
                            }.buttonStyle(.bordered).disabled(downloading)
                            if radio.role == "admin" {
                                Spacer()
                                Button("Eliminar", role: .destructive) { pendingDelete = file }.buttonStyle(.bordered).disabled(radio.filesBusy)
                            }
                        }
                    }.padding(.vertical, 5)
                }
            }
            .navigationTitle("Instructivos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if radio.role == "admin" { Button("Subir") { importing = true }.disabled(radio.filesBusy) }
                }
            }
            .task { await radio.loadFiles() }
            .refreshable { await radio.loadFiles() }
            .quickLookPreview($preview)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): Task { await radio.upload(url) }
                case .failure(let error): radio.error = error.localizedDescription; dismiss()
                }
            }
            .confirmationDialog("¿Eliminar este archivo para todo el equipo?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    if let file = pendingDelete { pendingDelete = nil; Task { await radio.delete(file) } }
                }
            }
            .onChange(of: radio.error) { if $0 != nil { dismiss() } }
        }
    }
}
