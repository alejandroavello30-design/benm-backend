import Foundation

struct RosterRow: Codable, Identifiable {
    var id = UUID()
    var user = ""
    var type = ""
    var sector = ""
    var filled: Bool { !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !type.isEmpty || !sector.isEmpty }
}

