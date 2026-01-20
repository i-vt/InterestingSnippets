// npm init -y
// npm i express socket.io multer cookie-parser uuid mime-types
// node WatchVideosTogether.js

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

// === CONFIGURATION ===
const PORT = process.env.PORT || 3000;
server.timeout = 0; 

// === SETUP ===
const UPLOADS_DIR = path.join(__dirname, "uploads");
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);
app.use(cookieParser());
app.use(express.json());

// === ADMIN KEY ===
const ADMIN_KEY = uuidv4();
const keyContent = `Admin Key: ${ADMIN_KEY}\nDate: ${new Date().toISOString()}`;
try {
    const tmpPath = path.join('/tmp', 'WatchTogetherKey.txt');
    fs.writeFileSync(tmpPath, keyContent);
    console.log(`ðŸ”‘ Admin Key saved to: ${tmpPath}`);
} catch (err) {
    const localPath = path.join(__dirname, 'WatchTogetherKey.txt');
    fs.writeFileSync(localPath, keyContent);
    console.log(`âš ï¸  Admin Key saved to: ${localPath}`);
}

// === UTILS ===
const ADJECTIVES = ["Happy", "Cool", "Super", "Fast", "Neon", "Cyber", "Mega", "Hyper", "Ultra", "Wild"];
const NOUNS = ["Panda", "Fox", "Wolf", "Tiger", "Bear", "Eagle", "Falcon", "Otter", "Dragon", "Shark"];

function generateUsername() {
  const adj = ADJECTIVES[Math.floor(Math.random() * ADJECTIVES.length)]; 
  const noun = NOUNS[Math.floor(Math.random() * NOUNS.length)];
  const num = Math.floor(Math.random() * 100);
  return `${adj}${noun}${num}`;
}

// === MULTER ===
const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, UPLOADS_DIR),
  filename: (_, file, cb) => {
    const ext = path.extname(file.originalname) || ".mp4";
    const nameWithoutExt = path.basename(file.originalname, ext);
    const safeName = nameWithoutExt.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 32);
    
    // UTC Timestamp
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const timeStr = `UTC${now.getUTCFullYear()}${pad(now.getUTCMonth()+1)}${pad(now.getUTCDate())}_${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
    
    cb(null, `${timeStr}_${safeName}_${uuidv4()}${ext}`);
  },
});

const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 * 1024 } });

// === STATE MANAGEMENT ===
const rooms = new Map(); 
const sessions = new Map(); 
const MAX_SESSIONS = 1000;

// === MIDDLEWARE ===
function checkAdminKey(req, res, next) {
  const providedKey = req.query.key || req.headers['x-admin-key'] || req.body.key;
  if (providedKey !== ADMIN_KEY) return res.status(403).json({ error: "Invalid Admin Key" });
  next();
}

// === ROUTES ===

// List Files
app.get("/files", checkAdminKey, (req, res) => {
    fs.readdir(UPLOADS_DIR, (err, files) => {
        if (err) return res.status(500).json({ error: "Disk Error" });
        const fileList = files
            .filter(f => !f.startsWith('.'))
            .map(filename => {
                try {
                    const stats = fs.statSync(path.join(UPLOADS_DIR, filename));
                    return {
                        name: filename,
                        url: `/uploads/${filename}`,
                        size: (stats.size / 1024 / 1024).toFixed(2) + " MB",
                        created: stats.birthtime
                    };
                } catch (e) { return null; }
            })
            .filter(Boolean)
            .sort((a, b) => b.created - a.created);
        res.json(fileList);
    });
});

// Rename File
app.post("/files/rename", checkAdminKey, (req, res) => {
    const { oldName, newName } = req.body;
    if (!oldName || !newName) return res.status(400).json({ error: "Missing filenames" });

    // Sanitize
    const safeNewName = path.basename(newName); 
    const oldPath = path.join(UPLOADS_DIR, oldName);
    const newPath = path.join(UPLOADS_DIR, safeNewName);

    if (!fs.existsSync(oldPath)) return res.status(404).json({ error: "File not found" });
    if (fs.existsSync(newPath)) return res.status(400).json({ error: "Filename already exists" });

    try {
        fs.renameSync(oldPath, newPath);
        res.json({ success: true, newName: safeNewName });
    } catch (err) {
        res.status(500).json({ error: "Failed to rename" });
    }
});

// Delete File
app.delete("/files/:filename", checkAdminKey, (req, res) => {
    const filename = req.params.filename;
    const filePath = path.join(UPLOADS_DIR, filename);
    if (filename.includes('..') || filename.includes('/')) return res.status(400).json({ error: "Invalid filename" });
    if (!fs.existsSync(filePath)) return res.status(404).json({ error: "File not found" });

    try {
        fs.unlinkSync(filePath);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: "Failed to delete" });
    }
});

// Upload
app.post("/upload", checkAdminKey, (req, res, next) => {
  req.setTimeout(4 * 60 * 60 * 1000); 
  next();
}, upload.single("video"), (req, res) => {
  if (!req.file) return res.status(400).json({ error: "No file provided" });
  res.json({ url: `/uploads/${req.file.filename}`, filename: req.file.filename });
}, (err, req, res, next) => {
  res.status(500).json({ error: err.message });
});

// Stream
app.get("/uploads/:filename", (req, res) => {
  const filePath = path.join(UPLOADS_DIR, req.params.filename);
  if (!fs.existsSync(filePath)) return res.status(404).send("File not found");

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;
  const mimeType = mime.lookup(filePath) || "video/mp4";

  if (!range) {
    res.writeHead(200, { "Content-Length": fileSize, "Content-Type": mimeType, "Accept-Ranges": "bytes" });
    fs.createReadStream(filePath).pipe(res);
  } else {
    const parts = range.replace(/bytes=/, "").split("-");
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    if (start >= fileSize) { res.status(416).send('Range not satisfiable'); return; }
    
    res.writeHead(206, {
      "Content-Range": `bytes ${start}-${end}/${fileSize}`,
      "Accept-Ranges": "bytes",
      "Content-Length": end - start + 1,
      "Content-Type": mimeType,
    });
    fs.createReadStream(filePath, { start, end }).pipe(res);
  }
});

app.get("/", (_, res) => res.redirect("/room?room=" + Math.random().toString(36).substring(2, 8)));

app.get("/room", (req, res) => {
  let sessionId = req.cookies.sessionId;
  let username;
  if (sessionId && sessions.has(sessionId)) {
    username = sessions.get(sessionId);
  } else {
    sessionId = uuidv4();
    username = generateUsername();
    sessions.set(sessionId, username);
    if (sessions.size > MAX_SESSIONS) sessions.delete(sessions.keys().next().value);
    res.cookie("sessionId", sessionId, { maxAge: 31536000000, httpOnly: true });
  }

  res.send(renderHTML(username));
});

// === FRONTEND TEMPLATE ===
function renderHTML(username) {
return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>WatchTogether Enterprise</title>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<script type="module" src="https://cdn.jsdelivr.net/npm/emoji-picker-element@^1/index.js"></script>
<style>
:root {
  --bg-dark: #0f172a;
  --bg-panel: #1e293b;
  --border: #334155;
  --primary: #3b82f6;
  --primary-hover: #2563eb;
  --text-main: #f1f5f9;
  --text-muted: #94a3b8;
  --success: #10b981;
  --danger: #ef4444;
}

* { box-sizing: border-box; }

body { 
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  background-color: var(--bg-dark);
  color: var(--text-main);
  margin: 0;
  height: 100vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* --- ICONS (SVG) --- */
.icon { width: 18px; height: 18px; fill: currentColor; }

/* --- TOASTS --- */
#toast-container { position: fixed; top: 20px; right: 20px; z-index: 9999; display: flex; flex-direction: column; gap: 10px; }
.toast {
  background: var(--bg-panel); border: 1px solid var(--border); padding: 12px 16px; border-radius: 6px;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.5); min-width: 250px; display: flex; align-items: center; gap: 10px;
  animation: slideIn 0.3s ease; font-size: 14px;
}
.toast.success { border-left: 4px solid var(--success); }
.toast.error { border-left: 4px solid var(--danger); }
.toast.info { border-left: 4px solid var(--primary); }
@keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }

/* --- HEADER --- */
header {
  height: 60px;
  background: rgba(30, 41, 59, 0.8);
  backdrop-filter: blur(10px);
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  flex-shrink: 0;
  z-index: 50;
}

.brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 18px; letter-spacing: -0.5px; }
.brand span { color: var(--primary); }
.room-badge { 
  background: rgba(59, 130, 246, 0.1); color: var(--primary); 
  padding: 4px 12px; border-radius: 99px; font-size: 12px; font-family: monospace; 
  cursor: pointer; transition: background 0.2s; display: flex; align-items: center; gap: 6px;
  border: 1px solid rgba(59, 130, 246, 0.2);
}
.room-badge:hover { background: rgba(59, 130, 246, 0.2); border-color: rgba(59, 130, 246, 0.4); }

.header-right { display: flex; gap: 10px; align-items: center; }

button.btn-icon {
  background: transparent; border: 1px solid var(--border); color: var(--text-muted);
  width: 36px; height: 36px; border-radius: 6px; cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: all 0.2s;
}
button.btn-icon:hover, button.btn-icon.active { background: var(--bg-panel); color: var(--text-main); border-color: var(--primary); }

/* --- CONTROLS PANEL (THE ISLES) --- */
#controlsPanel {
  position: absolute; top: 60px; left: 0; right: 0; background: rgba(15, 23, 42, 0.95);
  backdrop-filter: blur(10px); border-bottom: 1px solid var(--border);
  padding: 20px; transform: translateY(-110%); transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  z-index: 40; display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 20px;
}
#controlsPanel.open { transform: translateY(0); }

.control-isle { background: var(--bg-panel); border: 1px solid var(--border); border-radius: 8px; padding: 20px; }
.isle-title { font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted); font-weight: 700; margin-bottom: 15px; display: block; }

.input-row { display: flex; gap: 8px; margin-bottom: 12px; }
input[type="text"], input[type="file"], input[type="password"] {
  background: #0f172a; border: 1px solid var(--border); color: white; padding: 10px 12px; border-radius: 6px; width: 100%; font-size: 14px; outline: none; transition: border 0.2s;
}
input:focus { border-color: var(--primary); }

.btn {
  background: var(--primary); color: white; border: none; padding: 0 16px; height: 40px; border-radius: 6px;
  font-weight: 600; font-size: 14px; cursor: pointer; transition: background 0.2s; white-space: nowrap; display: flex; align-items: center; justify-content: center; gap: 6px;
}
.btn:hover { background: var(--primary-hover); }
.btn-secondary { background: var(--border); color: var(--text-main); }
.btn-secondary:hover { background: #475569; }

/* Range Slider */
input[type=range] { -webkit-appearance: none; width: 100%; background: transparent; }
input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; height: 16px; width: 16px; border-radius: 50%; background: var(--primary); cursor: pointer; margin-top: -6px; box-shadow: 0 0 0 2px var(--bg-panel); }
input[type=range]::-webkit-slider-runnable-track { width: 100%; height: 4px; background: var(--border); border-radius: 2px; }

/* File Browser */
#fileBrowser { margin-top: 15px; border: 1px solid var(--border); border-radius: 6px; max-height: 250px; overflow-y: auto; background: #0f172a; display: none; }
.file-item { padding: 10px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; font-size: 13px; gap: 10px; }
.file-item:last-child { border-bottom: none; }
.file-item:hover { background: rgba(255,255,255,0.03); }
.file-info { flex: 1; overflow: hidden; display: flex; flex-direction: column; }
.file-name { color: var(--text-main); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.file-size { color: var(--text-muted); font-size: 11px; }

.file-actions { display: flex; gap: 5px; }
.btn-xs { padding: 4px 8px; height: 26px; font-size: 11px; }
.btn-danger { background: var(--danger); }
.btn-warning { background: #f59e0b; }

/* Emoji Picker Customization */
emoji-picker {
    --background: var(--bg-panel);
    --border-color: var(--border);
    --input-border-color: var(--border);
    --input-font-color: var(--text-main);
    --category-font-color: var(--text-muted);
    width: 100%;
    height: 350px;
    border-radius: 6px;
    box-shadow: 0 -4px 10px rgba(0,0,0,0.5);
}

/* --- MAIN LAYOUT --- */
.main-container { display: flex; flex: 1; overflow: hidden; position: relative; }

/* Video Area */
.video-stage { 
  flex: 1; background: black; display: flex; align-items: center; justify-content: center; position: relative; 
}
video { width: 100%; height: 100%; max-height: calc(100vh - 60px); outline: none; }

/* Sidebar */
.sidebar { 
  width: 320px; background: var(--bg-panel); border-left: 1px solid var(--border); display: flex; flex-direction: column; 
  transition: width 0.3s ease; flex-shrink: 0;
}
.tabs { display: flex; border-bottom: 1px solid var(--border); }
.tab { flex: 1; padding: 12px; text-align: center; font-size: 13px; color: var(--text-muted); cursor: pointer; font-weight: 500; border-bottom: 2px solid transparent; }
.tab:hover { color: var(--text-main); background: rgba(255,255,255,0.02); }
.tab.active { color: var(--primary); border-bottom-color: var(--primary); }

.sidebar-content { flex: 1; overflow: hidden; display: flex; flex-direction: column; position: relative; }
.tab-pane { display: none; flex: 1; flex-direction: column; overflow: hidden; height: 100%; }
.tab-pane.active { display: flex; }

/* Chat */
#chatMessages { flex: 1; overflow-y: auto; padding: 15px; display: flex; flex-direction: column; gap: 8px; }
.message { font-size: 13px; line-height: 1.4; padding: 8px 10px; background: rgba(255,255,255,0.03); border-radius: 6px; display: flex; gap: 10px; }
.message.system { color: var(--text-muted); font-style: italic; background: transparent; padding: 4px 0; text-align: center; font-size: 12px; display: block; }
.msg-avatar { width: 32px; height: 32px; border-radius: 6px; background: var(--border); flex-shrink: 0; }
.msg-content { display: flex; flex-direction: column; overflow: hidden; }
.msg-user { color: var(--primary); font-weight: 600; font-size: 11px; margin-bottom: 2px; }
.chat-input-area { padding: 15px; border-top: 1px solid var(--border); background: rgba(15, 23, 42, 0.5); position: relative; }

/* Participants */
#participantsList { padding: 15px; overflow-y: auto; }
.participant-row { display: flex; align-items: center; gap: 10px; padding: 8px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }
.avatar-img { width: 32px; height: 32px; border-radius: 6px; background: var(--border); object-fit: cover; }
.p-name { font-size: 13px; }
.p-status { width: 8px; height: 8px; border-radius: 50%; background: var(--success); margin-left: auto; box-shadow: 0 0 5px rgba(16, 185, 129, 0.4); }

/* Progress Bar */
.progress-container { height: 4px; background: #334155; border-radius: 2px; margin-top: 10px; display: none; overflow: hidden; }
.progress-bar { height: 100%; background: var(--success); width: 0%; transition: width 0.1s; }

/* Mobile */
@media (max-width: 768px) {
  .main-container { flex-direction: column; }
  .video-stage { min-height: 250px; flex: none; }
  .sidebar { width: 100%; flex: 1; border-left: none; border-top: 1px solid var(--border); }
  #controlsPanel { grid-template-columns: 1fr; max-height: 70vh; overflow-y: auto; }
}
</style>
</head>
<body>

<div id="toast-container"></div>

<header>
  <div class="brand">
    <svg class="icon" viewBox="0 0 24 24"><path d="M4 6a2 2 0 012-2h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm2-2v12h12V4H6zm3.5 3v6l5-3-5-3z"/></svg>
    <span>Watch</span>Together
  </div>

  <div class="room-badge" id="roomSwitcher" title="Click to Change Room">
    <span>Room:</span>
    <span id="roomIdDisplay" style="font-weight:bold; color:#e2e8f0;"></span>
    <svg class="icon" style="width:12px; height:12px; opacity:0.7" viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
  </div>

  <div class="header-right">
    <button class="btn-icon" id="shareBtn" title="Copy Link">
        <svg class="icon" viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
    </button>

    <div id="connectionStatus" style="width:10px; height:10px; border-radius:50%; background:var(--danger); margin: 0 5px;" title="Disconnected"></div>
    
    <button class="btn-icon" id="toggleControls" title="Settings & Admin">
      <svg class="icon" viewBox="0 0 24 24"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.488.488 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 00-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.04.17 0 .4.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 00-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.58 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.04-.22 0-.45-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/></svg>
    </button>
  </div>
</header>

<div id="controlsPanel">
  <div class="control-isle">
    <span class="isle-title">Playback Controls</span>
    <div class="input-row">
      <input type="text" id="videoUrl" placeholder="Enter .mp4 URL here...">
      <button class="btn" id="loadBtn">Load</button>
    </div>
    <div style="display:flex; align-items:center; gap:15px; margin-top:15px;">
      <span style="font-size:12px; color:var(--text-muted); font-weight:600;">SPEED</span>
      <input type="range" id="speedSlider" min="0.25" max="2" step="0.25" value="1" style="flex:1;">
      <span id="speedValue" style="font-size:13px; font-variant-numeric: tabular-nums; width:30px;">1x</span>
      <button class="btn btn-secondary btn-xs" id="syncBtn">Sync</button>
    </div>
  </div>

  <div class="control-isle">
    <span class="isle-title">Admin Zone</span>
    <div class="input-row">
      <input type="password" id="adminKey" placeholder="Admin Key">
    </div>
    <div class="input-row">
      <input type="file" id="uploadInput" accept="video/*" style="padding:7px;">
      <button class="btn" id="uploadBtn">Upload</button>
    </div>
    <div class="progress-container" id="uploadProgress">
      <div class="progress-bar" id="progressFill"></div>
    </div>
    
    <div style="margin-top:15px; border-top:1px solid var(--border); padding-top:15px;">
      <button class="btn btn-secondary" id="browseBtn" style="width:100%">ðŸ“‚ Browse Files</button>
      <div id="fileBrowser"></div>
    </div>
  </div>
</div>

<div class="main-container">
  <div class="video-stage">
    <video id="player" controls playsinline></video>
  </div>

  <aside class="sidebar">
    <div class="tabs">
      <div class="tab active" onclick="switchTab('chat')">Chat</div>
      <div class="tab" onclick="switchTab('participants')">People (<span id="userCount">0</span>)</div>
    </div>

    <div class="sidebar-content">
      <div id="chatTab" class="tab-pane active">
        <div id="chatMessages"></div>
        <div class="chat-input-area">
          <emoji-picker class="dark" style="display:none; position: absolute; bottom: 100%; right: 0;"></emoji-picker>
          <div class="input-row" style="margin:0;">
            <button class="btn btn-secondary" id="emojiBtn" style="padding: 0 10px; font-size:16px;">ðŸ˜€</button>
            <input type="text" id="chatInput" placeholder="Say something...">
            <button class="btn" id="sendBtn">âž¤</button>
          </div>
        </div>
      </div>

      <div id="participantsTab" class="tab-pane">
        <div id="participantsList"></div>
      </div>
    </div>
  </aside>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
const socket = io();
const urlParams = new URLSearchParams(location.search);
const room = urlParams.get("room") || "default";
const myUsername = "${username}";

// --- UI INIT ---
document.getElementById("roomIdDisplay").textContent = room;

// --- TOAST SYSTEM ---
function showToast(msg, type='info') {
  const container = document.getElementById('toast-container');
  const el = document.createElement('div');
  el.className = \`toast \${type}\`;
  el.textContent = msg;
  container.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    setTimeout(() => el.remove(), 300);
  }, 4000);
}

// --- EMOJI PICKER ---
const emojiBtn = document.getElementById('emojiBtn');
const emojiPicker = document.querySelector('emoji-picker');
const chatInput = document.getElementById('chatInput');

emojiBtn.onclick = () => {
    emojiPicker.style.display = emojiPicker.style.display === 'none' ? 'block' : 'none';
};

emojiPicker.addEventListener('emoji-click', event => {
    chatInput.value += event.detail.unicode;
    chatInput.focus();
});

document.addEventListener('click', (e) => {
    if (!emojiPicker.contains(e.target) && e.target !== emojiBtn) {
        emojiPicker.style.display = 'none';
    }
});

// --- STATE VARIABLES ---
const player = document.getElementById("player");
let ignore = false;
let isSeeking = false;
let seekTimeout;
let ignoreTimeout;

// --- SOCKET CONNECTION ---
const statusDot = document.getElementById("connectionStatus");
socket.on("connect", () => {
  statusDot.style.background = "var(--success)";
  statusDot.title = "Connected";
  socket.emit("join", { room, username: myUsername });
});
socket.on("disconnect", () => {
  statusDot.style.background = "var(--danger)";
  statusDot.title = "Disconnected";
});

// --- CONTROLS TOGGLE ---
document.getElementById('toggleControls').onclick = (e) => {
  document.getElementById('controlsPanel').classList.toggle('open');
  e.currentTarget.classList.toggle('active');
};

// --- ROOM SWITCHING ---
document.getElementById('roomSwitcher').onclick = () => {
  const newRoom = prompt("Enter Room ID to switch to:", room);
  if(newRoom && newRoom !== room) {
    window.location.href = "/room?room=" + encodeURIComponent(newRoom);
  }
};

// --- COPY LINK ---
document.getElementById('shareBtn').onclick = () => {
  const url = window.location.href;
  navigator.clipboard.writeText(url).then(() => showToast("Link copied to clipboard!", "success"));
};

// --- TABS ---
window.switchTab = (tabName) => {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
  
  if(tabName === 'chat') {
    document.querySelector('.tab:nth-child(1)').classList.add('active');
    document.getElementById('chatTab').classList.add('active');
  } else {
    document.querySelector('.tab:nth-child(2)').classList.add('active');
    document.getElementById('participantsTab').classList.add('active');
  }
};

// --- FILE BROWSER & ADMIN ACTIONS ---
const browseBtn = document.getElementById('browseBtn');
const fileBrowser = document.getElementById('fileBrowser');

browseBtn.onclick = async () => {
  const key = document.getElementById('adminKey').value.trim();
  if(!key) return showToast("Admin Key required", "error");
  
  if(fileBrowser.style.display === 'block') {
    fileBrowser.style.display = 'none'; return;
  }

  browseBtn.textContent = "Loading...";
  try {
    const res = await fetch('/files?key=' + encodeURIComponent(key));
    if(!res.ok) throw new Error("Invalid Key or Server Error");
    const files = await res.json();
    
    fileBrowser.innerHTML = '';
    files.forEach(f => {
      const row = document.createElement('div');
      row.className = 'file-item';
      row.innerHTML = \`
        <div class="file-info">
          <div class="file-name" title="\${f.name}">\${f.name}</div>
          <div class="file-size">\${f.size}</div>
        </div>
        <div class="file-actions">
            <button class="btn btn-xs" onclick="loadVideo('\${f.url}')" title="Load">â–¶</button>
            <button class="btn btn-xs btn-warning" onclick="renameFile('\${f.name}')" title="Rename">âœï¸</button>
            <button class="btn btn-xs btn-danger" onclick="deleteFile('\${f.name}')" title="Delete">ðŸ—‘ï¸</button>
        </div>
      \`;
      fileBrowser.appendChild(row);
    });
    fileBrowser.style.display = 'block';
  } catch(e) {
    showToast(e.message, "error");
  } finally {
    browseBtn.textContent = "ðŸ“‚ Browse Files";
  }
};

window.loadVideo = (url) => {
  player.src = url;
  socket.emit("video:load", { room, url });
  document.getElementById('controlsPanel').classList.remove('open');
  showToast("Video loaded", "success");
};

window.deleteFile = async (filename) => {
    if(!confirm("Are you sure you want to delete " + filename + "?")) return;
    const key = document.getElementById('adminKey').value.trim();
    
    try {
        const res = await fetch('/files/' + encodeURIComponent(filename) + '?key=' + encodeURIComponent(key), {
            method: 'DELETE'
        });
        if(res.ok) {
            showToast("File deleted", "success");
            browseBtn.click(); setTimeout(() => browseBtn.click(), 50); // Refresh
        } else {
            showToast("Failed to delete", "error");
        }
    } catch(e) { showToast(e.message, "error"); }
};

window.renameFile = async (oldName) => {
    const newName = prompt("Enter new name for " + oldName + ":", oldName);
    if(!newName || newName === oldName) return;
    
    const key = document.getElementById('adminKey').value.trim();
    try {
        const res = await fetch('/files/rename', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key, oldName, newName })
        });
        const data = await res.json();
        if(res.ok) {
            showToast("Renamed to " + data.newName, "success");
            browseBtn.click(); setTimeout(() => browseBtn.click(), 50); // Refresh
        } else {
            showToast(data.error || "Failed to rename", "error");
        }
    } catch(e) { showToast(e.message, "error"); }
};


// --- UPLOAD ---
document.getElementById('uploadBtn').onclick = () => {
  const file = document.getElementById('uploadInput').files[0];
  const key = document.getElementById('adminKey').value.trim();
  if(!file || !key) return showToast("Missing file or key", "error");

  const form = new FormData();
  form.append("video", file);

  const xhr = new XMLHttpRequest();
  const progressCont = document.getElementById('uploadProgress');
  const progressFill = document.getElementById('progressFill');
  
  progressCont.style.display = 'block';
  xhr.upload.addEventListener('progress', (e) => {
    if (e.lengthComputable) progressFill.style.width = ((e.loaded / e.total) * 100) + '%';
  });

  xhr.onload = () => {
    progressCont.style.display = 'none';
    if (xhr.status === 200) {
      const data = JSON.parse(xhr.responseText);
      loadVideo(data.url);
      showToast("Upload Complete!", "success");
    } else {
      showToast("Upload Failed", "error");
    }
  };
  
  xhr.open('POST', '/upload?key=' + encodeURIComponent(key));
  xhr.send(form);
};

// --- VIDEO SYNC ---
document.getElementById('loadBtn').onclick = () => {
  const url = document.getElementById('videoUrl').value;
  if(url) loadVideo(url);
};

const speedSlider = document.getElementById('speedSlider');

// Update visual text immediately
speedSlider.oninput = (e) => {
  document.getElementById('speedValue').textContent = e.target.value + 'x';
};

// Send socket event ONLY when user releases the slider (prevents flooding)
speedSlider.onchange = (e) => {
  const speed = parseFloat(e.target.value);
  player.playbackRate = speed;
  socket.emit("video:speed", { room, speed, time: player.currentTime });
};

document.getElementById('syncBtn').onclick = () => {
  socket.emit("video:request-sync", { room });
  showToast("Sync requested", "info");
};

// --- CORE SYNC LOGIC ---
socket.on("video:state", (s) => {
  // If no state, ignore. 
  // NOTE: We REMOVED the 'isSeeking' check here. 
  // We still want to receive Pause/Speed events even if we are scrubbing.
  if(!s) return;
  
  // Set Ignore Flag and schedule reset
  ignore = true;
  clearTimeout(ignoreTimeout);
  
  // 1. URL Check
  if (s.videoUrl && s.videoUrl !== player.getAttribute('src')) {
    player.src = s.videoUrl;
  }
  
  // 2. Play/Pause Check (Always apply regardless of seeking)
  if (s.isPlaying && player.paused) {
      player.play().catch(()=>{});
  } else if (!s.isPlaying && !player.paused) {
      player.pause();
  }
  
  // 3. Time Sync Check (Only if NOT seeking locally)
  // This prevents the bar from jumping out from under your mouse while scrubbing
  if (!isSeeking) {
      const drift = Math.abs(player.currentTime - s.currentTime);
      if (drift > 1.0) {
        console.log("Syncing time. Drift:", drift);
        player.currentTime = s.currentTime;
      }
  }
  
  // 4. Speed Check
  if(s.playbackRate && player.playbackRate !== s.playbackRate) {
    player.playbackRate = s.playbackRate;
    document.getElementById('speedSlider').value = s.playbackRate;
    document.getElementById('speedValue').textContent = s.playbackRate + 'x';
  }

  // Reset ignore after DOM updates settle
  ignoreTimeout = setTimeout(() => {
      ignore = false;
  }, 50); 
});

// Video Events
player.onplay = () => {
    if(ignore) return;
    socket.emit("video:play", { room, time: player.currentTime });
};

player.onpause = () => {
    if(ignore) return;
    socket.emit("video:pause", { room, time: player.currentTime });
};

player.onseeking = () => {
    isSeeking = true;
    clearTimeout(seekTimeout);
};

player.onseeked = () => {
    if(ignore) return;
    clearTimeout(seekTimeout);
    // Debounce seek to prevent flooding
    seekTimeout = setTimeout(() => {
        isSeeking = false;
        socket.emit("video:seek", { room, time: player.currentTime });
    }, 200);
};

// Keyboard Shortcuts
document.addEventListener('keydown', (e) => {
  if(e.target.tagName === 'INPUT') return;
  if(e.code === 'Space') { e.preventDefault(); player.paused ? player.play() : player.pause(); }
  if(e.code === 'KeyF') { e.preventDefault(); document.fullscreenElement ? document.exitFullscreen() : player.requestFullscreen(); }
});

// --- CHAT ---
function addMsg(user, text, sys) {
  const d = document.createElement("div");
  d.className = "message" + (sys ? " system" : "");
  if(sys) {
    d.textContent = text;
  } else {
    // Show user avatar in message
    const avatarUrl = 'https://api.dicebear.com/9.x/dylan/svg?seed=' + user;
    d.innerHTML = \`
      <img src="\${avatarUrl}" class="msg-avatar" alt="\${user}">
      <div class="msg-content">
        <span class="msg-user">\${user}</span>
        <span>\${text}</span>
      </div>
    \`;
  }
  const c = document.getElementById("chatMessages");
  c.appendChild(d);
  c.scrollTop = c.scrollHeight;
}

socket.on("chat:message", d => addMsg(d.username, d.message, d.isSystem));
socket.on("chat:history", h => h.forEach(m => addMsg(m.username, m.message, m.isSystem)));

document.getElementById('sendBtn').onclick = () => {
  const i = document.getElementById('chatInput');
  if(i.value.trim()) {
    socket.emit("chat:send", { room, username: myUsername, message: i.value });
    i.value = "";
  }
};
document.getElementById('chatInput').onkeypress = (e) => {
  if(e.key === 'Enter') document.getElementById('sendBtn').click();
};

// --- PARTICIPANTS ---
socket.on("room:users", (users) => {
  const list = document.getElementById('participantsList');
  const count = document.getElementById('userCount');
  list.innerHTML = '';
  count.textContent = users.length;
  
  users.forEach(u => {
    const row = document.createElement('div');
    row.className = 'participant-row';
    const avatarUrl = 'https://api.dicebear.com/9.x/dylan/svg?seed=' + u;
    row.innerHTML = \`
      <img src="\${avatarUrl}" class="avatar-img" alt="\${u}">
      <div class="p-name">\${u} \${u === myUsername ? '(You)' : ''}</div>
      <div class="p-status"></div>
    \`;
    list.appendChild(row);
  });
});

</script>
</body>
</html>`;
}

// === SOCKET HELPER ===
const updateRoom = (room, data) => {
    const r = rooms.get(room);
    if(!r) return;
    
    // Update local state
    Object.assign(r, data, { lastUpdate: Date.now() });
    
    // BROADCAST TO EVERYONE (including sender) to ensure absolute sync
    io.to(room).emit("video:state", r);
};

// === SOCKET LOGIC ===
io.on("connection", (socket) => {
  socket.on("join", ({ room, username }) => {
    socket.join(room);
    socket.username = username;
    socket.room = room;
    
    if (!rooms.has(room)) {
      rooms.set(room, { 
        videoUrl: "", isPlaying: false, currentTime: 0, playbackRate: 1, 
        lastUpdate: Date.now(), chat: [], participants: new Set() 
      });
    }
    
    const r = rooms.get(room);
    r.participants.add(username); // Add user
    
    // Sync User
    let estimatedTime = r.currentTime;
    if(r.isPlaying) estimatedTime += (Date.now() - r.lastUpdate) / 1000 * r.playbackRate;
    
    socket.emit("video:state", { ...r, currentTime: estimatedTime });
    socket.emit("chat:history", r.chat);
    
    // Broadcast updates
    io.to(room).emit("chat:message", { username: "System", message: `${username} joined`, isSystem: true });
    io.to(room).emit("room:users", Array.from(r.participants));
  });

  socket.on("video:load", ({ room, url }) => {
      const r = rooms.get(room);
      if(r) {
        Object.assign(r, { videoUrl: url, currentTime: 0, isPlaying: false, lastUpdate: Date.now() });
        io.to(room).emit("video:state", r);
      }
  });
  
  socket.on("video:play", ({ room, time }) => updateRoom(room, { isPlaying: true, currentTime: time }));
  socket.on("video:pause", ({ room, time }) => updateRoom(room, { isPlaying: false, currentTime: time }));
  socket.on("video:seek", ({ room, time }) => updateRoom(room, { currentTime: time }));
  socket.on("video:speed", ({ room, speed, time }) => updateRoom(room, { playbackRate: speed, currentTime: time }));
  
  socket.on("video:request-sync", ({ room }) => {
      const r = rooms.get(room);
      if(r) {
          let liveTime = r.currentTime;
          if(r.isPlaying) liveTime += (Date.now() - r.lastUpdate) / 1000 * r.playbackRate;
          socket.emit("video:state", { ...r, currentTime: liveTime });
      }
  });

  socket.on("chat:send", ({ room, username, message }) => {
    const r = rooms.get(room);
    if (r) {
        const msg = { username, message, isSystem: false };
        r.chat.push(msg);
        if(r.chat.length > 50) r.chat.shift();
        io.to(room).emit("chat:message", msg);
    }
  });
  
  socket.on("disconnect", () => {
      if(socket.room) {
          const r = rooms.get(socket.room);
          if(r) {
             r.participants.delete(socket.username);
             io.to(socket.room).emit("chat:message", { username: "System", message: `${socket.username} left`, isSystem: true });
             io.to(socket.room).emit("room:users", Array.from(r.participants));
          }
      }
  });
});

server.listen(PORT, () => {
  console.log(`ðŸš€ Enterprise Server running at http://localhost:${PORT}`);
});
