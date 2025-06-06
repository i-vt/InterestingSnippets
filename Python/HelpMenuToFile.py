import io
import sys

# Create a string buffer
output = io.StringIO()

# Redirect stdout to the buffer
sys.stdout = output

# Call help on the object/module you want
help(str)  # You can replace `str` with any module, function, class, etc.

# Reset stdout
sys.stdout = sys.__stdout__

# Write the output to a file
with open("help_output.txt", "w", encoding="utf-8") as f:
    f.write(output.getvalue())

output.close()
