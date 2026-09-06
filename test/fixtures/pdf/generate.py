"""Regenerate our small, synthetic PDF reader fixtures (requires pypdf only)."""

from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import (
    ArrayObject, DecodedStreamObject, DictionaryObject, NameObject,
    NumberObject, TextStringObject,
)

ROOT = Path(__file__).parent


def dictionary(**items):
    return DictionaryObject({NameObject('/' + k): v for k, v in items.items()})


def stream(data):
    result = DecodedStreamObject()
    result.set_data(data)
    return result


def page(writer, text=None, japanese=False, image=False):
    result = writer.add_blank_page(width=400, height=300)
    if image:
        picture = stream(b'\x00\x00\x00')
        picture.update(dictionary(Type=NameObject('/XObject'), Subtype=NameObject('/Image'),
            Width=NumberObject(1), Height=NumberObject(1),
            ColorSpace=NameObject('/DeviceRGB'), BitsPerComponent=NumberObject(8)))
        result[NameObject('/Resources')] = dictionary(XObject=dictionary(Im1=writer._add_object(picture)))
        result[NameObject('/Contents')] = writer._add_object(stream(b'q 100 0 0 100 40 40 cm /Im1 Do Q'))
    elif text:
        if japanese:
            mappings = '\n'.join(f'<{ord(c):04X}> <{ord(c):04X}>' for c in sorted(set(text)))
            cmap = ('/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n'
                    '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
                    '/CMapName /TestUnicode def\n/CMapType 2 def\n'
                    '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'
                    f'{len(set(text))} beginbfchar\n{mappings}\nendbfchar\n'
                    'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend').encode()
            descendant = dictionary(Type=NameObject('/Font'), Subtype=NameObject('/CIDFontType0'),
                BaseFont=NameObject('/HeiseiMin-W3'),
                CIDSystemInfo=dictionary(Registry=TextStringObject('Adobe'),
                    Ordering=TextStringObject('Japan1'), Supplement=NumberObject(2)))
            font = dictionary(Type=NameObject('/Font'), Subtype=NameObject('/Type0'),
                BaseFont=NameObject('/HeiseiMin-W3'), Encoding=NameObject('/UniJIS-UCS2-H'),
                DescendantFonts=ArrayObject([writer._add_object(descendant)]),
                ToUnicode=writer._add_object(stream(cmap)))
            encoded = '<' + text.encode('utf-16-be').hex() + '>'
        else:
            font = dictionary(Type=NameObject('/Font'), Subtype=NameObject('/Type1'),
                BaseFont=NameObject('/Helvetica'))
            encoded = '(' + text + ')'
        result[NameObject('/Resources')] = dictionary(Font=dictionary(F1=writer._add_object(font)))
        result[NameObject('/Contents')] = writer._add_object(stream(
            f'BT /F1 14 Tf 40 200 Td {encoded} Tj ET'.encode()))


if __name__ == '__main__':
    writer = PdfWriter()
    page(writer, 'First page text.')
    page(writer, image=True)
    page(writer, '日本語の本文です。', japanese=True)
    page(writer)
    page(writer, 'Last page text.')
    writer.write(ROOT / 'text-pages.pdf')

    writer = PdfWriter()
    page(writer, image=True)
    writer.write(ROOT / 'image-only.pdf')

    for name, password in [('password.pdf', 'test-password'), ('empty-password.pdf', '')]:
        writer = PdfWriter()
        writer.clone_document_from_reader(PdfReader(ROOT / 'text-pages.pdf'))
        writer.encrypt(password, owner_password='test-owner')
        writer.write(ROOT / name)
