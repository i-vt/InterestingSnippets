# Step 1: Generate palette (preserves transparency)
ffmpeg -i shush.gif -filter_complex "[0:v] palettegen" -frames:v 1 palette.png

# Step 2: Resize + apply palette (preserves transparency + quality)
ffmpeg -i shush.gif -i palette.png \
-filter_complex "[0:v] scale=100:100:flags=lanczos[x];[x][1:v] paletteuse" \
shush1.gif
