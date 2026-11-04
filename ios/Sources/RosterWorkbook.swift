import Foundation

// OOXML with inline strings: user input is never interpreted as an Excel formula.
enum RosterWorkbook {
    static func xml(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 }.map(Character.init))
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func make(_ rows: [RosterRow]) -> Data {
        let selected = rows.enumerated().filter { $0.element.filled }
        let exported = selected.isEmpty ? Array(rows.enumerated()) : selected
        func cell(_ ref: String, _ text: String, style: Int = 0) -> String {
            "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(text))</t></is></c>"
        }
        var sheet = "<row r=\"1\">" + zip(["A1","B1","C1","D1"], ["N.º","Usuario","Tipo","Sector"]).map { cell($0.0, $0.1, style: 1) }.joined() + "</row>"
        for (offset, item) in exported.enumerated() {
            let n = offset + 2
            let color = ["Rojo": 2, "Amarillo": 3, "Verde": 4][item.element.sector] ?? 0
            sheet += "<row r=\"\(n)\"><c r=\"A\(n)\"><v>\(item.offset + 1)</v></c>" + cell("B\(n)", item.element.user) + cell("C\(n)", item.element.type) + cell("D\(n)", item.element.sector, style: color) + "</row>"
        }
        let files: [(String,String)] = [
            ("[Content_Types].xml", """
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """),
            ("_rels/.rels", """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Lista" sheetId="1" r:id="rId1"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """),
            ("xl/styles.xml", """
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF142D4E"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFCDD2"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF59D"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFC8E6C9"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/><xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyFill="1"/><xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
            """),
            ("xl/worksheets/sheet1.xml", """
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="8" customWidth="1"/><col min="2" max="2" width="36" customWidth="1"/><col min="3" max="4" width="20" customWidth="1"/></cols><sheetData>\(sheet)</sheetData><autoFilter ref="A1:D\(exported.count + 1)"/><dataValidations count="2"><dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="C2:C1048576"><formula1>"Funcionario,Paciente"</formula1></dataValidation><dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="D2:D1048576"><formula1>"Rojo,Amarillo,Verde"</formula1></dataValidation></dataValidations></worksheet>
            """)
        ]
        return StoredZIP.make(files.map { ($0.0, Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + $0.1).utf8)) })
    }
}

enum StoredZIP {
    static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ UInt32.max
    }
    static func make(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        func u16(_ v: UInt16) -> Data { var n = v.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        func u32(_ v: UInt32) -> Data { var n = v.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        for (name, bytes) in files {
            let path = Data(name.utf8), offset = UInt32(out.count), crc = crc32(bytes), size = UInt32(bytes.count)
            out += u32(0x04034b50)
            out += u16(20)
            out += u16(0x800)
            out += u16(0)
            out += u16(0)
            out += u16(0x21)
            out += u32(crc)
            out += u32(size)
            out += u32(size)
            out += u16(UInt16(path.count))
            out += u16(0)
            out += path
            out += bytes
            central += u32(0x02014b50)
            central += u16(20)
            central += u16(20)
            central += u16(0x800)
            central += u16(0)
            central += u16(0)
            central += u16(0x21)
            central += u32(crc)
            central += u32(size)
            central += u32(size)
            central += u16(UInt16(path.count))
            central += u16(0)
            central += u16(0)
            central += u16(0)
            central += u16(0)
            central += u32(0)
            central += u32(offset)
            central += path
        }
        let offset = UInt32(out.count)
        out += central
        out += u32(0x06054b50)
        out += u16(0)
        out += u16(0)
        out += u16(UInt16(files.count))
        out += u16(UInt16(files.count))
        out += u32(UInt32(central.count))
        out += u32(offset)
        out += u16(0)
        return out
    }
}
