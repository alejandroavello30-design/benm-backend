from zipfile import ZipFile
import xml.etree.ElementTree as E
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with ZipFile('lista-prueba.xlsx') as z:
    assert z.testzip() is None
    for path in z.namelist(): E.fromstring(z.read(path))
    s=E.fromstring(z.read('xl/worksheets/sheet1.xml'))
    rows=s.findall('s:sheetData/s:row',ns)
    assert len(rows)==3
    assert rows[2].find('s:c/s:v',ns).text=='20'
    assert rows[1].findall('s:c',ns)[1].find('s:is/s:t',ns).text=='José & María <Equipo>'
    assert rows[2].findall('s:c',ns)[1].find('s:is/s:t',ns).text=='=1+1'
    assert not s.findall('.//s:f',ns)
    assert len(s.findall('s:dataValidations/s:dataValidation',ns))==2
with ZipFile('lista-vacia.xlsx') as z:
    s=E.fromstring(z.read('xl/worksheets/sheet1.xml'))
    assert len(s.findall('s:sheetData/s:row',ns))==21
print('XLSX: ZIP, XML, escaping, literal formulas, numbering, dropdowns and 20 blank rows verified.')
