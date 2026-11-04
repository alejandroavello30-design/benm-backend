import Foundation

@main struct Verify {
    static func main() throws {
        var rows = (0..<20).map { _ in RosterRow() }
        rows[0].user = "José & María <Equipo>"
        rows[0].type = "Funcionario"; rows[0].sector = "Rojo"
        rows[19].user = "=1+1"; rows[19].type = "Paciente"; rows[19].sector = "Verde"
        try RosterWorkbook.make(rows).write(to: URL(fileURLWithPath: "lista-prueba.xlsx"))
        try RosterWorkbook.make((0..<20).map { _ in RosterRow() }).write(to: URL(fileURLWithPath: "lista-vacia.xlsx"))
    }
}
