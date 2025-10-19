// SharedVideoPlayer.js
const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const multer = require("multer");
const fs = require("fs");
const path = require("path");
const { v4: uuidv4 } = require("uuid");
const mime = require("mime-types");

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// === SETUP ===
const UPLOADS_DIR = path.join(__dirname, "uploads");
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);
app.use("/uploads", express.static(UPLOADS_DIR)); // ✅ serve files correctly

const ADMIN_KEY = uuidv4();
console.log("🔑 Admin Upload Key:", ADMIN_KEY);

// === Multer (video uploads) ===
const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, UPLOADS_DIR),
  filename: (_, file, cb) => {
    const ext = path.extname(file.originalname) || ".mp4";
    cb(null, uuidv4() + ext);
  },
});
const upload = multer({ storage });

// === In-memory shared rooms ===
const rooms = new Map();

// === Upload route ===
app.post("/upload", upload.single("video"), (req, res) => {
  if (req.query.key !== ADMIN_KEY) return res.status(403).send("❌ Invalid admin key");
  if (!req.file) return res.status(400).send("❌ No video file uploaded");

  const filePath = path.join(UPLOADS_DIR, req.file.filename);
  if (!fs.existsSync(filePath)) {
    console.error("🚫 File missing right after upload:", filePath);
    return res.status(500).send("Internal error saving file");
  }

  const fileUrl = `/uploads/${req.file.filename}`;
  console.log("✅ Uploaded:", fileUrl);
  res.json({ url: fileUrl });
});

// === Video streaming with Range support ===
app.get("/uploads/:filename", (req, res) => {
  const filePath = path.join(UPLOADS_DIR, req.params.filename);
  if (!fs.existsSync(filePath)) return res.status(404).send("File not found");

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;
  const mimeType = mime.lookup(filePath) || "video/mp4";

  if (!range) {
    res.writeHead(200, {
      "Content-Length": fileSize,
      "Content-Type": mimeType,
    });
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  const [startStr, endStr] = range.replace(/bytes=/, "").split("-");
  const start = parseInt(startStr, 10);
  const end = endStr ? parseInt(endStr, 10) : fileSize - 1;
  if (start >= fileSize || end >= fileSize) {
    res.writeHead(416, { "Content-Range": `bytes */${fileSize}` });
    return res.end();
  }

  const chunkSize = end - start + 1;
  const fileStream = fs.createReadStream(filePath, { start, end });
  res.writeHead(206, {
    "Content-Range": `bytes ${start}-${end}/${fileSize}`,
    "Accept-Ranges": "bytes",
    "Content-Length": chunkSize,
    "Content-Type": mimeType,
  });
  fileStream.pipe(res);
  fileStream.on("error", (err) => {
    console.error("Stream error:", err);
    res.end();
  });
});

// === Redirect root to random room ===
app.get("/", (_, res) => {
  const id = Math.random().toString(36).substring(2, 8);
  res.redirect("/room?room=" + id);
});

// === Serve the client page ===
app.get("/room", (_, res) => {
  res.type("html").send(`<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>🎬 Shared Video Player</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: system-ui, sans-serif; background:#111; color:#eee; text-align:center; margin:0; }
header { padding:10px; background:#222; border-bottom:1px solid #333; }
video { width:80%; max-width:800px; margin-top:20px; border-radius:8px; background:#000; }
input,button { margin:4px; padding:6px 10px; border-radius:6px; border:none; }
button { background:#333; color:white; cursor:pointer; }
button:hover { background:#555; }
</style>
</head>
<body>
<header>
  <h2>🎥 Shared Video Room</h2>
  <input id="videoUrl" placeholder="Video URL (mp4/webm)" size="40">
  <button id="loadBtn">Load</button>
  <br>
  <input type="password" id="adminKey" placeholder="Admin Key">
  <input type="file" id="uploadInput" accept="video/*">
  <button id="uploadBtn">Upload</button>
</header>
<video id="player" controls muted></video>
<div style="margin-top:10px;">
  <button id="unmuteBtn" style="background:#d44; font-size:16px;">🔇 Click to Enable Sound</button>
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
const room = new URLSearchParams(location.search).get("room") || "main";
const socket = io();
const player = document.getElementById("player");
const videoUrl = document.getElementById("videoUrl");
const loadBtn = document.getElementById("loadBtn");
const uploadBtn = document.getElementById("uploadBtn");
const uploadInput = document.getElementById("uploadInput");
const adminKey = document.getElementById("adminKey");
const unmuteBtn = document.getElementById("unmuteBtn");

let ignore = false;
let currentSource = "";
let seekTimeout = null;
let isSeeking = false;

// Unmute handler
unmuteBtn.onclick = () => {
  player.muted = false;
  unmuteBtn.style.display = "none";
};

// Hide button if user unmutes via video controls
player.onvolumechange = () => {
  if (!player.muted) unmuteBtn.style.display = "none";
};

// join room
socket.emit("join", { room });
socket.on("video:state", applyState);
socket.on("video:update", applyState);

function applyState(s) {
  if (!s) return;
  
  // Don't apply remote updates while user is actively seeking
  if (isSeeking) return;
  
  ignore = true;

  // only reload when new video
  if (s.videoUrl && s.videoUrl !== currentSource) {
    currentSource = s.videoUrl;
    player.src = s.videoUrl;
    player.load();
    player.onloadedmetadata = () => {
      player.currentTime = s.currentTime || 0;
      if (s.isPlaying) player.play().catch(() => {});
    };
  } else {
    if (Math.abs(player.currentTime - (s.currentTime || 0)) > 0.5)
      player.currentTime = s.currentTime || 0;
    if (s.isPlaying && player.paused)
      player.play().catch(() => {});
    else if (!s.isPlaying && !player.paused)
      player.pause();
  }

  ignore = false;
}

// FIX: Send current time with play/pause events
player.onplay = () => !ignore && socket.emit("video:play", { room, time: player.currentTime });
player.onpause = () => !ignore && socket.emit("video:pause", { room, time: player.currentTime });

// FIX: Debounce seek events to prevent lag during scrubbing
player.onseeking = () => {
  isSeeking = true;
  clearTimeout(seekTimeout);
};

player.onseeked = () => {
  if (ignore) return;
  
  clearTimeout(seekTimeout);
  seekTimeout = setTimeout(() => {
    isSeeking = false;
    socket.emit("video:seek", { room, time: player.currentTime });
  }, 300); // Wait 300ms after user stops seeking
};

loadBtn.onclick = () => {
  const url = videoUrl.value.trim();
  if (url) socket.emit("video:load", { room, url });
};

// === UPLOAD VIDEO ===
uploadBtn.onclick = async () => {
  const file = uploadInput.files[0];
  const key = adminKey.value.trim();
  if (!file || !key) return alert("Enter admin key and select a file.");

  const form = new FormData();
  form.append("video", file);

  const res = await fetch("/upload?key=" + encodeURIComponent(key), {
    method: "POST",
    body: form,
  });
  if (!res.ok) return alert(await res.text());

  const data = await res.json();
  const videoPath = data.url;
  console.log("Uploaded:", videoPath);

  player.src = videoPath;
  player.load();
  player.onloadedmetadata = () => {
    currentSource = videoPath;
    socket.emit("video:load", { room, url: videoPath });
  };
};
</script>
</body>
</html>`);
});

// === Socket logic ===
io.on("connection", (socket) => {
  socket.on("join", ({ room }) => {
    socket.join(room);
    if (!rooms.has(room))
      rooms.set(room, { videoUrl: "", isPlaying: false, currentTime: 0 });
    socket.emit("video:state", rooms.get(room));
  });

  socket.on("video:load", ({ room, url }) => {
    const s = rooms.get(room) || {};
    Object.assign(s, { videoUrl: url, currentTime: 0, isPlaying: false });
    rooms.set(room, s);
    io.to(room).emit("video:update", s);
  });

  // FIX: Update currentTime when playing
  socket.on("video:play", ({ room, time }) => {
    const s = rooms.get(room); if (!s) return;
    s.isPlaying = true;
    s.currentTime = time || 0;
    socket.to(room).emit("video:update", s); // Don't send back to sender
  });

  // FIX: Update currentTime when pausing
  socket.on("video:pause", ({ room, time }) => {
    const s = rooms.get(room); if (!s) return;
    s.isPlaying = false;
    s.currentTime = time || 0;
    socket.to(room).emit("video:update", s); // Don't send back to sender
  });

  // FIX: Don't send seek event back to sender
  socket.on("video:seek", ({ room, time }) => {
    const s = rooms.get(room); if (!s) return;
    s.currentTime = time;
    socket.to(room).emit("video:update", s); // Don't send back to sender
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log("🚀 Shared Video Player at http://localhost:" + PORT);
  console.log("🔑 Admin Upload Key:", ADMIN_KEY);
});
