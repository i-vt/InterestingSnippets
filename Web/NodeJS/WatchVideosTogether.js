// npm init -y
// npm i express socket.io multer cookie-parser 
// node SharedVideoPlayer.js

const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const multer = require("multer");
const fs = require("fs");
const path = require("path");
const { v4: uuidv4 } = require("uuid");
const mime = require("mime-types");
const cookieParser = require("cookie-parser");

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// === SETUP ===
const UPLOADS_DIR = path.join(__dirname, "uploads");
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);
app.use("/uploads", express.static(UPLOADS_DIR));
app.use(cookieParser());

const ADMIN_KEY = uuidv4();

// === Username Generation ===
const COLORS = ["Red", "Blue", "Green", "Purple", "Orange", "Pink", "Yellow", "Teal", "Coral", "Violet", "Gold", "Silver", "Crimson", "Azure", "Emerald"];
const ANIMALS = ["Panda", "Fox", "Wolf", "Tiger", "Bear", "Eagle", "Dolphin", "Owl", "Lion", "Penguin", "Hawk", "Otter", "Lynx", "Raven", "Falcon"];

function generateUsername() {
  const color = COLORS[Math.floor(Math.random() * COLORS.length)];
  const animal = ANIMALS[Math.floor(Math.random() * ANIMALS.length)];
  return `${color}${animal}`;
}

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

// === Session management (max 1000 sessions) ===
const sessions = new Map(); // sessionId -> username
const MAX_SESSIONS = 1000;

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
app.get("/room", (req, res) => {
  // Get or create session
  let sessionId = req.cookies.sessionId;
  let username;
  
  if (sessionId && sessions.has(sessionId)) {
    // Existing session - retrieve username from server
    username = sessions.get(sessionId);
  } else {
    // New session - generate both session ID and username
    sessionId = uuidv4();
    username = generateUsername();
    
    // Store in sessions map
    sessions.set(sessionId, username);
    
    // Enforce max sessions limit (FIFO)
    if (sessions.size > MAX_SESSIONS) {
      const firstKey = sessions.keys().next().value;
      sessions.delete(firstKey);
    }
    
    // Set session cookie (1 year expiry)
    res.cookie("sessionId", sessionId, { 
      maxAge: 365 * 24 * 60 * 60 * 1000, 
      httpOnly: true 
    });
  }
  
  res.type("html").send(`<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>🎬 Shared Video Player</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
* { box-sizing: border-box; }
body { 
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; 
  background: #0a0a0a; 
  color: #e4e4e7; 
  margin: 0; 
  display: flex; 
  flex-direction: column; 
  height: 100vh; 
}

/* ===== ENTERPRISE HEADER ===== */
header {
  background: linear-gradient(135deg, #1a1a1d 0%, #0f0f11 100%);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
  flex-shrink: 0;
  position: relative;
  z-index: 100;
}

.header-container {
  max-width: 1600px;
  margin: 0 auto;
  padding: 0 24px;
}

.header-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.brand {
  display: flex;
  align-items: center;
  gap: 12px;
}

.logo {
  width: 40px;
  height: 40px;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.brand-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.brand-title {
  font-size: 18px;
  font-weight: 600;
  color: #f4f4f5;
  margin: 0;
  letter-spacing: -0.02em;
}

.brand-subtitle {
  font-size: 11px;
  color: #71717a;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.room-info {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  background: rgba(255, 255, 255, 0.04);
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.room-label {
  font-size: 12px;
  color: #a1a1aa;
  font-weight: 500;
}

.room-id {
  font-family: 'Courier New', monospace;
  color: #3b82f6;
  font-weight: 600;
  font-size: 13px;
}

.header-controls {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 16px;
  padding: 16px 0;
  align-items: start;
}

.control-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.section-label {
  font-size: 11px;
  color: #a1a1aa;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 4px;
}

.input-group {
  display: flex;
  gap: 8px;
  align-items: center;
}

.input-wrapper {
  position: relative;
  flex: 1;
  min-width: 0;
}

.input-icon {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: #71717a;
  font-size: 14px;
}

input[type="text"],
input[type="password"] {
  width: 100%;
  padding: 10px 12px 10px 36px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  color: #f4f4f5;
  font-size: 14px;
  transition: all 0.2s ease;
  font-family: inherit;
}

input[type="text"]:focus,
input[type="password"]:focus {
  outline: none;
  border-color: #3b82f6;
  background: rgba(255, 255, 255, 0.08);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

input[type="text"]::placeholder,
input[type="password"]::placeholder {
  color: #52525b;
}

input[type="file"] {
  display: none;
}

.file-upload-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  color: #e4e4e7;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: 500;
}

.file-upload-btn:hover {
  background: rgba(255, 255, 255, 0.1);
  border-color: rgba(255, 255, 255, 0.18);
}

.btn {
  padding: 10px 20px;
  border-radius: 8px;
  border: none;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  white-space: nowrap;
  font-family: inherit;
}

.btn-primary {
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  color: white;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
}

.btn-primary:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

.btn-primary:active {
  transform: translateY(0);
}

.btn-secondary {
  background: rgba(255, 255, 255, 0.08);
  color: #e4e4e7;
  border: 1px solid rgba(255, 255, 255, 0.12);
}

.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.12);
  border-color: rgba(255, 255, 255, 0.18);
}

.upload-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* ===== MAIN CONTENT ===== */
.main-content { display:flex; flex:1; overflow:hidden; }
.video-section { flex:1; display:flex; flex-direction:column; align-items:center; padding:20px; overflow-y:auto; }
.chat-section { width:320px; background:#0f0f11; border-left:1px solid rgba(255, 255, 255, 0.1); display:flex; flex-direction:column; }
video { width:100%; max-width:900px; border-radius:12px; background:#000; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6); }

#unmuteBtn { 
  background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); 
  color: white;
  font-size: 16px; 
  margin-top: 16px; 
  padding: 12px 24px;
  border-radius: 8px;
  border: none;
  cursor: pointer;
  font-weight: 600;
  box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3);
  transition: all 0.2s ease;
}

#unmuteBtn:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(239, 68, 68, 0.4);
}

/* Chat styles */
.chat-header { padding:16px; background: rgba(255, 255, 255, 0.04); border-bottom:1px solid rgba(255, 255, 255, 0.08); font-weight:600; font-size: 14px; }
.chat-messages { flex:1; overflow-y:auto; padding:16px; }
.message { margin-bottom:12px; word-wrap:break-word; }
.message .username { font-weight:600; color:#3b82f6; margin-right:6px; }
.message .text { color:#d4d4d8; }
.message.system { opacity:0.6; font-style:italic; font-size: 13px; }
.message.system .text { color:#a1a1aa; }
.chat-input-area { padding:16px; background: rgba(255, 255, 255, 0.04); border-top:1px solid rgba(255, 255, 255, 0.08); }
#chatInput { 
  width:calc(100% - 70px); 
  padding:10px 12px; 
  border-radius:8px; 
  background: rgba(255, 255, 255, 0.06); 
  color:#f4f4f5; 
  border:1px solid rgba(255, 255, 255, 0.12);
  font-size: 14px;
  font-family: inherit;
}
#chatInput:focus {
  outline: none;
  border-color: #3b82f6;
  background: rgba(255, 255, 255, 0.08);
}
#sendBtn { 
  width:60px; 
  padding:10px; 
  background:#3b82f6; 
  color: white;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
  transition: all 0.2s ease;
}
#sendBtn:hover { 
  background:#2563eb; 
  transform: translateY(-1px);
}
.your-username { 
  padding:12px 16px; 
  text-align:center; 
  color:#3b82f6; 
  font-size:12px; 
  background: rgba(59, 130, 246, 0.08); 
  font-weight: 500;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

/* Responsive */
@media (max-width: 1024px) {
  .header-controls {
    grid-template-columns: 1fr;
  }
  
  .upload-section {
    flex-direction: row;
    flex-wrap: wrap;
  }
}

@media (max-width: 768px) {
  .header-top {
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }
  
  .room-info {
    width: 100%;
    justify-content: center;
  }
  
  .main-content { 
    flex-direction:column; 
  }
  
  .chat-section { 
    width:100%; 
    max-height:300px; 
    border-left:none; 
    border-top:1px solid rgba(255, 255, 255, 0.1); 
  }
  
  .input-group {
    flex-direction: column;
  }
  
  .btn {
    width: 100%;
    justify-content: center;
  }
}

@media (max-width: 480px) {
  .header-container {
    padding: 0 16px;
  }
  
  .brand-title {
    font-size: 16px;
  }
  
  .logo {
    width: 36px;
    height: 36px;
    font-size: 18px;
  }
}
</style>
</head>
<body>
<header>
  <div class="header-container">
    <div class="header-top">
      <div class="brand">
        <div class="logo">🎬</div>
        <div class="brand-text">
          <h1 class="brand-title">StreamSync</h1>
          <div class="brand-subtitle">Enterprise Video Platform</div>
        </div>
      </div>
      <div class="room-info">
        <span class="room-label">Room:</span>
        <span class="room-id" id="roomIdDisplay"></span>
      </div>
    </div>
    
    <div class="header-controls">
      <div class="control-section">
        <label class="section-label">🎥 Load Video</label>
        <div class="input-group">
          <div class="input-wrapper">
            <span class="input-icon">🔗</span>
            <input type="text" id="videoUrl" placeholder="Enter video URL (mp4, webm)">
          </div>
          <button class="btn btn-primary" id="loadBtn">
            <span>▶</span> Load Video
          </button>
        </div>
      </div>
      
      <div class="upload-section">
        <label class="section-label">📤 Admin Upload</label>
        <div class="input-group">
          <div class="input-wrapper">
            <span class="input-icon">🔑</span>
            <input type="password" id="adminKey" placeholder="Admin Key">
          </div>
          <label for="uploadInput" class="file-upload-btn">
            <span>📁</span> Choose File
          </label>
          <input type="file" id="uploadInput" accept="video/*">
          <button class="btn btn-primary" id="uploadBtn">
            <span>⬆</span> Upload
          </button>
        </div>
      </div>
    </div>
  </div>
</header>

<div class="main-content">
  <div class="video-section">
    <video id="player" controls muted></video>
    <button id="unmuteBtn">🔇 Click to Enable Sound</button>
  </div>
  <div class="chat-section">
    <div class="chat-header">💬 Live Chat</div>
    <div class="your-username">You are: <span id="displayUsername">${username}</span></div>
    <div class="chat-messages" id="chatMessages"></div>
    <div class="chat-input-area">
      <input type="text" id="chatInput" placeholder="Type a message..." maxlength="500">
      <button id="sendBtn">Send</button>
    </div>
  </div>
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
const room = new URLSearchParams(location.search).get("room") || "main";
document.getElementById("roomIdDisplay").textContent = room;

const socket = io();
const player = document.getElementById("player");
const videoUrl = document.getElementById("videoUrl");
const loadBtn = document.getElementById("loadBtn");
const uploadBtn = document.getElementById("uploadBtn");
const uploadInput = document.getElementById("uploadInput");
const adminKey = document.getElementById("adminKey");
const unmuteBtn = document.getElementById("unmuteBtn");
const chatInput = document.getElementById("chatInput");
const sendBtn = document.getElementById("sendBtn");
const chatMessages = document.getElementById("chatMessages");

let ignore = false;
let currentSource = "";
let seekTimeout = null;
let isSeeking = false;

// Username is provided by server
const myUsername = "${username}";

// Update file input label when file is selected
uploadInput.onchange = (e) => {
  const label = document.querySelector('.file-upload-btn');
  if (e.target.files[0]) {
    label.innerHTML = \`<span>📁</span> \${e.target.files[0].name}\`;
  }
};

// Unmute handler
unmuteBtn.onclick = () => {
  player.muted = false;
  unmuteBtn.style.display = "none";
};

player.onvolumechange = () => {
  if (!player.muted) unmuteBtn.style.display = "none";
};

// === VIDEO SYNC ===
socket.emit("join", { room, username: myUsername });
socket.on("video:state", applyState);
socket.on("video:update", applyState);

function applyState(s) {
  if (!s) return;
  if (isSeeking) return;
  
  ignore = true;

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

player.onplay = () => !ignore && socket.emit("video:play", { room, time: player.currentTime });
player.onpause = () => !ignore && socket.emit("video:pause", { room, time: player.currentTime });

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
  }, 300);
};

loadBtn.onclick = () => {
  const url = videoUrl.value.trim();
  if (url) socket.emit("video:load", { room, url });
};

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

// === CHAT ===
socket.on("chat:message", (data) => {
  addMessage(data.username, data.message, data.isSystem);
});

socket.on("chat:history", (messages) => {
  messages.forEach(msg => addMessage(msg.username, msg.message, msg.isSystem));
});

function addMessage(username, text, isSystem = false) {
  const msg = document.createElement("div");
  msg.className = "message" + (isSystem ? " system" : "");
  
  const userSpan = document.createElement("span");
  userSpan.className = "username";
  userSpan.textContent = username + ":";
  
  const textSpan = document.createElement("span");
  textSpan.className = "text";
  textSpan.textContent = text;
  
  msg.appendChild(userSpan);
  msg.appendChild(textSpan);
  chatMessages.appendChild(msg);
  chatMessages.scrollTop = chatMessages.scrollHeight;
}

function sendMessage() {
  const text = chatInput.value.trim();
  if (!text) return;
  
  socket.emit("chat:send", { room, username: myUsername, message: text });
  chatInput.value = "";
}

sendBtn.onclick = sendMessage;
chatInput.onkeypress = (e) => {
  if (e.key === "Enter") sendMessage();
};
</script>
</body>
</html>`);
});

// === Socket logic ===
io.on("connection", (socket) => {
  socket.on("join", ({ room, username }) => {
    socket.join(room);
    
    // Initialize room if needed
    if (!rooms.has(room)) {
      rooms.set(room, { 
        videoUrl: "", 
        isPlaying: false, 
        currentTime: 0,
        chatHistory: []
      });
    }
    
    const roomData = rooms.get(room);
    
    // Send video state
    socket.emit("video:state", {
      videoUrl: roomData.videoUrl,
      isPlaying: roomData.isPlaying,
      currentTime: roomData.currentTime
    });
    
    // Send chat history
    socket.emit("chat:history", roomData.chatHistory);
    
    // Announce user joined
    const joinMsg = {
      username: "System",
      message: `${username} joined the room`,
      isSystem: true,
      timestamp: Date.now()
    };
    roomData.chatHistory.push(joinMsg);
    if (roomData.chatHistory.length > 100) roomData.chatHistory.shift();
    
    io.to(room).emit("chat:message", joinMsg);
  });

  socket.on("video:load", ({ room, url }) => {
    const s = rooms.get(room);
    if (!s) return;
    Object.assign(s, { videoUrl: url, currentTime: 0, isPlaying: false });
    io.to(room).emit("video:update", s);
  });

  socket.on("video:play", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.isPlaying = true;
    s.currentTime = time || 0;
    socket.to(room).emit("video:update", s);
  });

  socket.on("video:pause", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.isPlaying = false;
    s.currentTime = time || 0;
    socket.to(room).emit("video:update", s);
  });

  socket.on("video:seek", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.currentTime = time;
    socket.to(room).emit("video:update", s);
  });

  socket.on("chat:send", ({ room, username, message }) => {
    const roomData = rooms.get(room);
    if (!roomData) return;
    
    const msg = {
      username,
      message,
      isSystem: false,
      timestamp: Date.now()
    };
    
    roomData.chatHistory.push(msg);
    if (roomData.chatHistory.length > 100) roomData.chatHistory.shift();
    
    io.to(room).emit("chat:message", msg);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log("🚀 Shared Video Player at http://localhost:" + PORT);
  console.log("🔑 Admin Upload Key:", ADMIN_KEY);
});
