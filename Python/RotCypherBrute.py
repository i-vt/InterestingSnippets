import binascii

hex_string = "tqxxa iadxp"

# Convert hex to bytes
try:
    raw_bytes = binascii.unhexlify(hex_string)
except binascii.Error:
    print("Invalid hex input!")
    exit()

# Define ROT function
def rot(text, shift):
    result = []
    for char in text:
        if 32 <= char <= 126:  # Printable ASCII range
            shifted = (char - 32 + shift) % 95 + 32
            result.append(chr(shifted))
        else:
            result.append(chr(char))  # Keep non-printable characters unchanged
    return ''.join(result)

# Bruteforce all ROT shifts
for shift in range(1, 26):  # ROT1 to ROT25
    decoded_text = rot(raw_bytes, shift)
    print(f"ROT{shift}: {decoded_text}\n")
