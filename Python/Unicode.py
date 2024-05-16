def is_unicode_notation(input_string):
    unicode_pattern = re.compile(r'(\\u[0-9a-fA-F]{4})+')
    match = unicode_pattern.fullmatch(input_string)
    return match is not None


def to_unicode_notation(input_string):
    # "⍺𝐛" -> "\\u237a\\u1d41b"
    unicode_notations = []
    for char in input_string: unicode_notations.append(f"\\u{ord(char):04x}")
    return ''.join(unicode_notations)

def unicode_escape_to_char(escape):
    hex_value = int(escape[2:], 16) #Ignore \u
    return chr(hex_value)
