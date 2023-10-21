# Must-know VIM shortcuts


1. **Navigation**:
   - `h`, `j`, `k`, `l`: Move the cursor left, down, up, and right, respectively.
   - `w` and `b`: Move forward and backward by words.
   - `0` and `$`: Move to the beginning and end of a line.
   - `G`: Go to the end of the file, and `gg`: Go to the beginning of the file.
   - `Ctrl+u` and `Ctrl+d`: Scroll up and down half a page.
   - `Ctrl+b` and `Ctrl+f`: Scroll up and down a full page.

2. **Editing**:
   - `i` and `a`: Enter insert mode before and after the cursor.
   - `I` and `A`: Insert at the beginning or end of the current line.
   - `o` and `O`: Open a new line below or above the current line and enter insert mode.
   - `u` and `Ctrl+r`: Undo and redo.
   - `yy` and `p`: Copy (yank) and paste lines.
   - `dd`: Delete a line.
   - `x` and `X`: Delete characters under and before the cursor.
   - `:w` and `:q`: Save and quit, respectively.

3. **Searching and Replacing**:
   - `/` and `?`: Start a forward or backward search.
   - `n` and `N`: Navigate to the next and previous search results.
   - `:%s/old/new/g`: Replace all occurrences of "old" with "new" in the entire file.

4. **Visual Mode**:
   - `v`: Start character-wise visual mode for selecting text.
   - `V`: Start line-wise visual mode.
   - `Ctrl+v`: Start block-wise visual mode.

5. **Miscellaneous**:
   - `:e filename`: Open a new file for editing.
   - `:wq` or `ZZ`: Save and quit.
   - `:q!`: Quit without saving changes.
   - `:e!`: Revert changes to the last saved version of the file.

6. **Buffers and Windows**:
   - `:e filename`: Open a new file in the current buffer.
   - `:bnext` and `:bprev`: Switch between buffers.
   - `:split` and `:vsplit`: Split the current window horizontally or vertically.
   - `Ctrl-w` followed by arrow keys: Navigate between split windows.
