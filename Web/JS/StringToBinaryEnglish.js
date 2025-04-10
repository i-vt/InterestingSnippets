//Character Encoding: JavaScript's .charCodeAt(0) method returns the UTF-16 code unit of the character at the specified index. For most common characters (i.e., those within the Basic Multilingual Plane, which includes characters from many of the world's writing systems), this will return a complete and correct code. However, for characters outside of this plane (such as many emoji or rare script characters)
function stringToBinaryen(input) {
    const zeroReplacement = '0';
    const oneReplacement = '1';
  
    return btoa(input
      .split('')
      .map(char => {
        let binary = char.charCodeAt(0).toString(2);
        binary = binary.padStart(8, '0');
        return binary
          .split('')
          .map(bit => (bit === '0' ? zeroReplacement : oneReplacement))
          .join('');
      })
      .join(' '));
}
