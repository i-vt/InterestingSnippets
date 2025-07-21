```
ffmpeg -framerate 2 -i PFP%03d.png -vf "scale=512:-1:flags=lanczos" -loop 0 output.gif
```
