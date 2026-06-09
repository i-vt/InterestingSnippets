import fitz  # PyMuPDF
import sys
import re

DEBUG = True
DEBUG_PAGE_LIMIT = 1

IDENTITY = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]

def mat_mul(m1, m2):
    a1,b1,c1,d1,e1,f1 = m1
    a2,b2,c2,d2,e2,f2 = m2
    return [a1*a2+c1*b2, b1*a2+d1*b2,
            a1*c2+c1*d2, b1*c2+d1*d2,
            a1*e2+c1*f2+e1, b1*e2+d1*f2+f1]

def mat_apply(m, x, y):
    a,b,c,d,e,f = m
    return a*x+c*y+e, b*x+d*y+f

_xobj_cache = {}

def get_xobjects(doc, owner_xref):
    key = (id(doc), owner_xref)
    if key in _xobj_cache:
        return _xobj_cache[key]
    mapping = {}
    try:
        obj_str  = doc.xref_object(owner_xref, compressed=False)
        res_ref  = re.search(r'/Resources\s+(\d+)\s+0\s+R', obj_str)
        res_str  = doc.xref_object(int(res_ref.group(1)), compressed=False) \
                   if res_ref else obj_str
        xobj_ref = re.search(r'/XObject\s+(\d+)\s+0\s+R', res_str)
        xobj_str = doc.xref_object(int(xobj_ref.group(1)), compressed=False) \
                   if xobj_ref else ''
        if not xobj_str:
            xobj_m   = re.search(r'/XObject\s*<<([^>]*)>>', res_str)
            xobj_str = xobj_m.group(1) if xobj_m else ''
        for m in re.finditer(r'/(\w+)\s+(\d+)\s+0\s+R', xobj_str):
            mapping[m.group(1)] = int(m.group(2))
    except Exception:
        pass
    _xobj_cache[key] = mapping
    return mapping

def get_xobj_matrix(doc, xref):
    try:
        obj_str = doc.xref_object(xref, compressed=False)
        m = re.search(r'/Matrix\s*\[([^\]]+)\]', obj_str)
        if m:
            vals = [float(v) for v in
                    re.findall(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?', m.group(1))]
            if len(vals) == 6:
                return vals
    except Exception:
        pass
    return list(IDENTITY)

# ── FIX 1: require at least one digit — prevents float('.') crash ─────────────
_TOK = re.compile(
    r'(-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)'       # number (≥1 digit required)
    r'|\b(BT|ET|Tm|Td|TD|T\*|cm|q|Q|Do)\b'            # tracked operators
    r'|(/\w+)'                                          # PDF name
    r'|\((?:[^\\()]|\\.)*\)'                            # literal string
    r'|<[0-9A-Fa-f\s]*>',                              # hex string
    re.DOTALL
)

# ── FIX 2: get precise character origins from get_text instead of coarse ──────
#           search_for bounding rect, eliminating false positives.
def get_char_origins(page, censored_text, debug=False):
    """
    Return list of (x, y) in PDF space (bottom-left origin) for the first
    character of each rendered span containing the censored text.
    These are used as tight 5 pt point targets in scan_stream, replacing
    the coarse search_for bounding rect that was causing 84-100 false matches.
    """
    H      = page.rect.height
    needle = censored_text.lower()
    origins = []

    try:
        raw = page.get_text("rawdict", flags=fitz.TEXT_PRESERVE_WHITESPACE)
    except Exception:
        return origins

    for block in raw.get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            line_text = "".join(s.get("text", "") for s in line.get("spans", []))
            if needle not in line_text.lower():
                continue
            for span in line.get("spans", []):
                chars = span.get("chars", [])
                if not chars:
                    continue
                ox, oy = chars[0]["origin"]      # PyMuPDF space (top-left, y↓)
                pdf_y  = H - oy                  # → PDF space   (bot-left, y↑)
                origins.append((ox, pdf_y))
                if debug:
                    print(f"    char origin: pymupdf=({ox:.2f},{oy:.2f}) "
                          f"→ pdf=({ox:.2f},{pdf_y:.2f})")
                break   # one anchor per line is sufficient
    return origins


def scan_stream(doc, stream_xref, res_xref, ctm, visited,
                target_rects, tolerance, debug):
    if stream_xref in visited:
        return []
    visited.add(stream_xref)

    try:
        raw = doc.xref_stream(stream_xref)
        if not raw:
            return []
        stream = raw.decode('latin-1')
    except Exception:
        return []

    matches   = []
    cur_ctm   = list(ctm)
    ctm_stk   = []
    in_bt     = False
    bt_start  = 0
    bt_hit    = False
    tm        = list(IDENTITY)
    lm        = list(IDENTITY)
    nums      = []
    last_name = None

    def hits(px, py):
        t = tolerance
        return any(x0-t <= px <= x1+t and y0-t <= py <= y1+t
                   for x0,y0,x1,y1 in target_rects)

    for tok in _TOK.finditer(stream):
        g1, g2, g3 = tok.group(1), tok.group(2), tok.group(3)

        if g1:
            nums.append(float(g1)); continue
        if g3:
            last_name = g3[1:];     continue
        if not g2:
            continue

        op = g2

        if op == 'q':
            ctm_stk.append(list(cur_ctm)); nums.clear()

        elif op == 'Q':
            if ctm_stk: cur_ctm = ctm_stk.pop()
            nums.clear()

        elif op == 'cm':
            if len(nums) >= 6:
                cur_ctm = mat_mul(cur_ctm, nums[-6:])
                if debug:
                    print(f"        cm  → CTM [{','.join(f'{v:.3f}' for v in cur_ctm)}]")
            nums.clear()

        elif op == 'Do':
            name = last_name
            if name:
                xmap       = get_xobjects(doc, res_xref)
                child_xref = xmap.get(name)
                if child_xref and child_xref not in visited:
                    child_mat = get_xobj_matrix(doc, child_xref)
                    child_ctm = mat_mul(cur_ctm, child_mat)
                    if debug:
                        print(f"        Do /{name} → xref {child_xref}  "
                              f"child CTM [{','.join(f'{v:.3f}' for v in child_ctm)}]")
                    sub = scan_stream(doc, child_xref, child_xref,
                                      child_ctm, visited, target_rects, tolerance, debug)
                    matches.extend(sub)
            last_name = None; nums.clear()

        elif op == 'BT':
            in_bt = True; bt_start = tok.start()
            tm = list(IDENTITY); lm = list(IDENTITY)
            bt_hit = False; nums.clear()

        elif op == 'ET':
            if in_bt and bt_hit:
                matches.append((stream_xref, bt_start, tok.end()))
                if debug:
                    print(f"        ✓ BT [{bt_start}:{tok.end()}] MATCHED xref {stream_xref}")
            in_bt = False; nums.clear()

        elif in_bt:
            if op == 'Tm':
                if len(nums) >= 6:
                    tm = list(nums[-6:]); lm = list(nums[-6:])
                    px, py = mat_apply(cur_ctm, tm[4], tm[5])
                    h = hits(px, py)
                    if debug:
                        print(f"        Tm  e={tm[4]:.1f} f={tm[5]:.1f} "
                              f"→ page ({px:.1f},{py:.1f})"
                              + ("  *** HIT" if h else ""))
                    if h: bt_hit = True
                nums.clear()

            elif op in ('Td', 'TD'):
                if len(nums) >= 2:
                    tx, ty = nums[-2], nums[-1]
                    # Update line matrix: Tlm' = Tlm × translate(tx,ty)
                    lm[4] = tx*lm[0] + ty*lm[2] + lm[4]
                    lm[5] = tx*lm[1] + ty*lm[3] + lm[5]
                    tm = list(lm)
                    px, py = mat_apply(cur_ctm, tm[4], tm[5])
                    h = hits(px, py)
                    if debug:
                        print(f"        Td  ({tx:.1f},{ty:.1f}) "
                              f"→ page ({px:.1f},{py:.1f})"
                              + ("  *** HIT" if h else ""))
                    if h: bt_hit = True
                nums.clear()

            elif op == 'T*':
                px, py = mat_apply(cur_ctm, tm[4], tm[5])
                if hits(px, py): bt_hit = True
                nums.clear()

            else:
                nums.clear()
        else:
            nums.clear()

    return matches


def inject_tr3(doc, matches, debug=False):
    by_xref = {}
    for xref, start, end in matches:
        by_xref.setdefault(xref, []).append((start, end))

    total = 0
    for xref, spans in by_xref.items():
        try:
            stream = doc.xref_stream(xref).decode('latin-1')
        except Exception:
            continue
        out, offset = stream, 0
        for start, end in sorted(spans):
            blk     = stream[start:end]
            patched = 'BT\n3 Tr' + blk[2:blk.rfind('ET')] + '0 Tr\nET'
            s, e    = start + offset, end + offset
            out     = out[:s] + patched + out[e:]
            offset += len(patched) - len(blk)
            total  += 1
        doc.update_stream(xref, out.encode('latin-1'))
        if debug:
            print(f"    Wrote {len(spans)} Tr=3 patch(es) to xref {xref}.")
    return total


def censor_page(doc, page, censored_text, debug=False):
    rects = page.search_for(censored_text)
    if not rects:
        return

    H      = page.rect.height
    needle = censored_text.lower()

    # Get precise character origins BEFORE clean_contents (same rendered result,
    # but avoids any edge-case interaction with stream normalisation).
    char_origins = get_char_origins(page, censored_text, debug=debug)

    if char_origins:
        # 5 pt point targets — typically matches exactly 1 BT block per instance
        target_rects = [(ox-5, oy-5, ox+5, oy+5) for ox, oy in char_origins]
        tolerance    = 5
        if debug:
            print(f"    Tight targets ({len(char_origins)}): "
                  f"{[(round(ox,1),round(oy,1)) for ox,oy in char_origins]}")
    else:
        # Fallback: coarse search_for rects (may over-censor on scaled/rotated text)
        target_rects = [(r.x0, H-r.y1, r.x1, H-r.y0) for r in rects]
        tolerance    = 8
        if debug:
            print(f"    Fallback to search_for rects (no rawdict origins found)")

    if debug:
        print(f"    Target rects (PDF spc): "
              f"{[(round(x0,1),round(y0,1),round(x1,1),round(y1,1)) for x0,y0,x1,y1 in target_rects]}")

    page.clean_contents()

    visited = set()
    matches = []
    for sc_xref in page.get_contents():
        sub = scan_stream(doc, sc_xref, page.xref, list(IDENTITY),
                          visited, target_rects, tolerance, debug)
        matches.extend(sub)

    # Widgets (AcroForm fields)
    for w in page.widgets():
        val = str(w.field_value or '')
        if debug:
            print(f"    Widget '{w.field_name}': value='{val[:60]}'")
        if needle in val.lower():
            w.field_value = ''; w.update()
            print(f"    ✓ Widget '{w.field_name}' cleared.")

    # Non-widget annotations
    for a in page.annots():
        content = a.info.get('content', '') or ''
        if needle in content.lower():
            info = a.info
            info['content'] = re.sub(re.escape(censored_text), '',
                                     content, flags=re.IGNORECASE)
            a.set_info(info); a.update()
            print(f"    ✓ Annotation censored.")

    if matches:
        n = inject_tr3(doc, matches, debug=debug)
        print(f"    ✓ Censored {n} BT block(s).")
    else:
        print(f"    ✗ No match."
              + (" (see debug above)" if debug else " Re-run with DEBUG=True."))


def process_pdf(input_path, output_path, top_margin_pt, bottom_margin_pt,
                text_to_remove):
    print(f"Opening '{input_path}'...")
    try:
        doc = fitz.open(input_path)
    except Exception as e:
        print(f"Error: {e}"); sys.exit(1)

    debug_rem = DEBUG_PAGE_LIMIT

    for page_num in range(len(doc)):
        page    = doc[page_num]
        w, h    = page.rect.width, page.rect.height
        instances = page.search_for(text_to_remove)

        if instances:
            do_debug = DEBUG and debug_rem > 0
            print(f"  Page {page_num+1}: {len(instances)} instance(s)."
                  + ("  [DEBUG]" if do_debug else ""))
            censor_page(doc, page, text_to_remove, debug=do_debug)
            if do_debug:
                debug_rem -= 1

        page.draw_rect(fitz.Rect(0, 0, w, top_margin_pt),
                       color=(1,1,1), fill=(1,1,1))
        page.draw_rect(fitz.Rect(0, h-bottom_margin_pt, w, h),
                       color=(1,1,1), fill=(1,1,1))

    print(f"Saving to '{output_path}'...")
    doc.save(output_path, garbage=4, deflate=True)
    doc.close()
    print("Done!")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("Usage: python script.py <input> <output> <top_pt> <bottom_pt> <text>")
        sys.exit(1)

    f_in, f_out = sys.argv[1], sys.argv[2]
    try:
        top, bot = float(sys.argv[3]), float(sys.argv[4])
    except ValueError:
        print("Error: crop values must be valid numbers."); sys.exit(1)

    process_pdf(f_in, f_out, top, bot, sys.argv[5])
