function caesarDecrypt(input, shift) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const alphabetLength = alphabet.length;
  let output = "";

  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    const pos = alphabet.indexOf(char);
    if (pos !== -1) {
      let newPos = (pos - shift) % alphabetLength;
      if (newPos < 0) {
        newPos += alphabetLength;
      }
      output += alphabet[newPos];
    } else {
      output += char;
    }
  }
  return output;
}
