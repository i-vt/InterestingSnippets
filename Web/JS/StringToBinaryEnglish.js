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
