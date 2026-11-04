import SwiftUI
import UniformTypeIdentifiers

@MainActor final class RosterStore: ObservableObject {
    @Published var rows: [RosterRow] { didSet { save() } }
    @Published var error: String?
    private let file: URL
    init() {
        file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("benm-lista.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { rows = try JSONDecoder().decode([RosterRow].self, from: Data(contentsOf: file)) }
            catch { rows = []; self.error = "No se pudo leer la lista guardada. El archivo original se conserva. \(error.localizedDescription)" }
        } else { rows = (0..<20).map { _ in RosterRow() } }
    }
    func save() {
        do { try JSONEncoder().encode(rows).write(to: file, options: .atomic) }
        catch { self.error = "No se pudo guardar la lista: \(error.localizedDescription)" }
    }
    func clear() { rows = (0..<20).map { _ in RosterRow() } }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct RosterView: View {
    @StateObject private var store = RosterStore()
    @Environment(\.dismiss) private var dismiss
    @State private var clearPrompt = false
    @State private var export = false
    @State private var document = ExportDocument(data: Data())
    private let xlsx = UTType(filenameExtension: "xlsx") ?? .data
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Lista guardada en este iPhone. Exporta el archivo para reunirlo con las listas del equipo.").font(.footnote)
                    HStack {
                        Button { store.rows.append(RosterRow()) } label: { Label("Agregar fila", systemImage: "plus") }
                        Spacer()
                        Button("Exportar Excel") { document = ExportDocument(data: RosterWorkbook.make(store.rows)); export = true }
                    }
                }
                ForEach(Array(store.rows.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(index + 1)").font(.headline).frame(width: 32)
                            TextField("Usuario", text: $store.rows[index].user)
                                .onChange(of: store.rows[index].user) { value in
                                    if value.count > 120 { store.rows[index].user = String(value.prefix(120)) }
                                }
                        }
                        HStack {
                            Picker("Tipo", selection: $store.rows[index].type) {
                                Text("Elegir").tag("")
                                Text("Funcionario").tag("Funcionario")
                                Text("Paciente").tag("Paciente")
                            }
                            Picker("Sector", selection: $store.rows[index].sector) {
                                Text("Elegir").tag("")
                                ForEach(["Rojo", "Amarillo", "Verde"], id: \.self) { Text($0).tag($0) }
                            }.tint(store.rows[index].sector == "Rojo" ? .red : store.rows[index].sector == "Amarillo" ? .yellow : .green)
                        }.font(.subheadline)
                    }.padding(.vertical, 5)
                }
                Button("Limpiar planilla", role: .destructive) { clearPrompt = true }
            }
            .navigationTitle("Lista")
            .toolbar { Button("Cerrar") { dismiss() } }
            .confirmationDialog("¿Borrar toda la lista de este iPhone?", isPresented: $clearPrompt, titleVisibility: .visible) {
                Button("Limpiar planilla", role: .destructive) { store.clear() }
                Button("Cancelar", role: .cancel) {}
            }
            .fileExporter(isPresented: $export, document: document, contentType: xlsx, defaultFilename: "BENM-lista-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .alert("Lista", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Aceptar") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}
