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
const sessions = new Map();
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
  let sessionId = req.cookies.sessionId;
  let username;
  
  if (sessionId && sessions.has(sessionId)) {
    username = sessions.get(sessionId);
  } else {
    sessionId = uuidv4();
    username = generateUsername();
    sessions.set(sessionId, username);
    
    if (sessions.size > MAX_SESSIONS) {
      const firstKey = sessions.keys().next().value;
      sessions.delete(firstKey);
    }
    
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
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
* { 
  box-sizing: border-box; 
  -webkit-tap-highlight-color: transparent;
}

body { 
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; 
  background: #0a0a0a; 
  color: #e4e4e7; 
  margin: 0; 
  display: flex; 
  flex-direction: column; 
  height: 100vh; 
  overflow: hidden;
  -webkit-font-smoothing: antialiased;
}

/* ===== DESKTOP HEADER ===== */
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
  height: 42px;
  padding: 0 12px 0 36px;
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
  justify-content: center;
  gap: 8px;
  height: 42px;
  padding: 0 16px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  color: #e4e4e7;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: 500;
  white-space: nowrap;
}

.file-upload-btn:hover {
  background: rgba(255, 255, 255, 0.1);
  border-color: rgba(255, 255, 255, 0.18);
}

.btn {
  height: 42px;
  padding: 0 20px;
  border-radius: 8px;
  border: 1px solid transparent;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  display: inline-flex;
  align-items: center;
  justify-content: center;
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

.upload-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* ===== MAIN CONTENT ===== */
.main-content { 
  display: flex; 
  flex: 1; 
  overflow: hidden;
}

.video-section { 
  flex: 1; 
  display: flex; 
  flex-direction: column; 
  align-items: center; 
  padding: 20px; 
  overflow-y: auto;
}

.chat-section { 
  width: 320px; 
  background: #0f0f11; 
  border-left: 1px solid rgba(255, 255, 255, 0.1); 
  display: flex; 
  flex-direction: column;
}

video { 
  width: 100%; 
  max-width: 900px; 
  border-radius: 12px; 
  background: #000; 
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
}

.player-controls {
  margin-top: 20px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
  width: 100%;
  max-width: 900px;
}

.speed-control {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 20px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  max-width: 400px;
}

.speed-label {
  font-size: 13px;
  color: #a1a1aa;
  font-weight: 600;
  white-space: nowrap;
}

.speed-slider {
  width: 180px;
  height: 6px;
  -webkit-appearance: none;
  appearance: none;
  background: rgba(255, 255, 255, 0.12);
  border-radius: 3px;
  outline: none;
  cursor: pointer;
}

.speed-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  cursor: pointer;
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.4);
}

.speed-slider::-moz-range-thumb {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  cursor: pointer;
  border: none;
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.4);
}

.speed-value {
  font-size: 14px;
  color: #3b82f6;
  font-weight: 600;
  min-width: 45px;
  text-align: center;
}

#unmuteBtn { 
  background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); 
  color: white;
  font-size: 16px; 
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
.chat-header { 
  padding: 16px; 
  background: rgba(255, 255, 255, 0.04); 
  border-bottom: 1px solid rgba(255, 255, 255, 0.08); 
  font-weight: 600; 
  font-size: 14px;
}

.your-username { 
  padding: 12px 16px; 
  text-align: center; 
  color: #3b82f6; 
  font-size: 12px; 
  background: rgba(59, 130, 246, 0.08); 
  font-weight: 500;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.chat-messages { 
  flex: 1; 
  overflow-y: auto; 
  padding: 16px;
}

.message { 
  margin-bottom: 12px; 
  word-wrap: break-word;
}

.message .username { 
  font-weight: 600; 
  color: #3b82f6; 
  margin-right: 6px;
}

.message .text { 
  color: #d4d4d8;
}

.message.system { 
  opacity: 0.6; 
  font-style: italic; 
  font-size: 13px;
}

.message.system .text { 
  color: #a1a1aa;
}

.chat-input-area { 
  padding: 16px; 
  background: rgba(255, 255, 255, 0.04); 
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}

#chatInput { 
  width: calc(100% - 70px); 
  padding: 10px 12px; 
  border-radius: 8px; 
  background: rgba(255, 255, 255, 0.06); 
  color: #f4f4f5; 
  border: 1px solid rgba(255, 255, 255, 0.12);
  font-size: 14px;
  font-family: inherit;
}

#chatInput:focus {
  outline: none;
  border-color: #3b82f6;
  background: rgba(255, 255, 255, 0.08);
}

#sendBtn { 
  width: 60px; 
  padding: 10px; 
  background: #3b82f6; 
  color: white;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
  transition: all 0.2s ease;
}

#sendBtn:hover { 
  background: #2563eb; 
  transform: translateY(-1px);
}

/* ===== MOBILE-SPECIFIC STYLES ===== */
.mobile-header {
  display: none;
}

.mobile-tabs {
  display: none;
}

.mobile-menu-btn {
  display: none;
}

.mobile-controls-drawer {
  display: none;
}

/* ===== MOBILE BREAKPOINT ===== */
@media (max-width: 768px) {
  /* Hide desktop header */
  header {
    display: none;
  }

  /* Show mobile header */
  .mobile-header {
    display: flex;
    flex-direction: column;
    background: linear-gradient(180deg, #1e1b4b 0%, #312e81 100%);
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.4);
    position: relative;
    z-index: 100;
  }

  .mobile-header-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
  }

  .mobile-brand {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .mobile-logo {
    width: 36px;
    height: 36px;
    background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    box-shadow: 0 2px 8px rgba(245, 158, 11, 0.4);
  }

  .mobile-title {
    font-size: 16px;
    font-weight: 700;
    color: #fef3c7;
    margin: 0;
  }

  .mobile-room-badge {
    padding: 6px 12px;
    background: rgba(255, 255, 255, 0.15);
    border-radius: 20px;
    font-size: 11px;
    font-weight: 600;
    color: #fef3c7;
    backdrop-filter: blur(10px);
  }

  .mobile-menu-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 8px;
    color: #fef3c7;
    font-size: 20px;
    cursor: pointer;
    transition: all 0.2s ease;
  }

  .mobile-menu-btn:active {
    transform: scale(0.95);
    background: rgba(255, 255, 255, 0.15);
  }

  .mobile-user-badge {
    padding: 8px 16px;
    background: rgba(0, 0, 0, 0.2);
    text-align: center;
    font-size: 12px;
    color: #fde68a;
    font-weight: 500;
  }

  /* Mobile controls drawer */
  .mobile-controls-drawer {
    display: block;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.9);
    z-index: 200;
    transform: translateY(-100%);
    transition: transform 0.3s ease;
    overflow-y: auto;
    padding: 20px;
  }

  .mobile-controls-drawer.active {
    transform: translateY(0);
  }

  .drawer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
  }

  .drawer-title {
    font-size: 20px;
    font-weight: 700;
    color: #f59e0b;
  }

  .drawer-close {
    width: 40px;
    height: 40px;
    background: rgba(255, 255, 255, 0.1);
    border: none;
    border-radius: 50%;
    color: #e4e4e7;
    font-size: 24px;
    cursor: pointer;
  }

  .drawer-section {
    margin-bottom: 24px;
  }

  .drawer-section-label {
    font-size: 12px;
    color: #f59e0b;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin-bottom: 12px;
  }

  .drawer-input-group {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .drawer-input {
    width: 100%;
    height: 48px;
    padding: 0 16px;
    background: rgba(255, 255, 255, 0.08);
    border: 2px solid rgba(249, 115, 22, 0.3);
    border-radius: 12px;
    color: #f4f4f5;
    font-size: 15px;
  }

  .drawer-input:focus {
    outline: none;
    border-color: #f59e0b;
    background: rgba(255, 255, 255, 0.12);
  }

  .drawer-btn {
    width: 100%;
    height: 48px;
    background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
    color: white;
    border: none;
    border-radius: 12px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    box-shadow: 0 4px 12px rgba(245, 158, 11, 0.3);
  }

  .drawer-btn:active {
    transform: scale(0.98);
  }

  .drawer-file-label {
    width: 100%;
    height: 48px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    background: rgba(255, 255, 255, 0.08);
    border: 2px dashed rgba(249, 115, 22, 0.3);
    border-radius: 12px;
    color: #fde68a;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
  }

  /* Mobile tabs */
  .mobile-tabs {
    display: flex;
    background: #1e1b4b;
    border-bottom: 2px solid rgba(245, 158, 11, 0.3);
  }

  .mobile-tab {
    flex: 1;
    padding: 14px;
    background: transparent;
    border: none;
    color: #a78bfa;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    position: relative;
  }

  .mobile-tab.active {
    color: #fde68a;
    background: rgba(245, 158, 11, 0.1);
  }

  .mobile-tab.active::after {
    content: '';
    position: absolute;
    bottom: -2px;
    left: 0;
    right: 0;
    height: 2px;
    background: linear-gradient(90deg, #f59e0b 0%, #f97316 100%);
  }

  /* Mobile content */
  .main-content {
    flex-direction: column;
    background: #0a0a0a;
  }

  .video-section,
  .chat-section {
    display: none;
    width: 100%;
    border: none;
  }

  .video-section.active,
  .chat-section.active {
    display: flex;
  }

  .video-section {
    padding: 0;
    overflow: hidden;
  }

  .video-section.active {
    display: flex;
    flex-direction: column;
    height: 100%;
  }

  video {
    width: 100%;
    max-width: 100%;
    border-radius: 0;
    flex-shrink: 0;
  }

  .player-controls {
    margin-top: 16px;
    padding: 0 16px 16px;
    gap: 12px;
  }

  .speed-control {
    width: 100%;
    max-width: 100%;
    background: rgba(245, 158, 11, 0.1);
    border: 1px solid rgba(245, 158, 11, 0.3);
    padding: 10px 16px;
  }

  .speed-label {
    color: #fde68a;
  }

  .speed-slider {
    flex: 1;
  }

  .speed-slider::-webkit-slider-thumb {
    background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
    width: 22px;
    height: 22px;
  }

  .speed-slider::-moz-range-thumb {
    background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
    width: 22px;
    height: 22px;
  }

  .speed-value {
    color: #f59e0b;
  }

  #unmuteBtn {
    background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%);
    font-size: 15px;
    padding: 12px 20px;
    width: 100%;
    max-width: 300px;
  }

  /* Mobile chat */
  .chat-section.active {
    background: #0a0a0a;
  }

  .chat-header {
    background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%);
    color: #fde68a;
    padding: 14px 16px;
    border-bottom: 2px solid rgba(245, 158, 11, 0.3);
  }

  .your-username {
    background: rgba(245, 158, 11, 0.1);
    color: #fde68a;
    border-bottom: 1px solid rgba(245, 158, 11, 0.2);
  }

  .chat-messages {
    background: #0a0a0a;
  }

  .message .username {
    color: #f59e0b;
  }

  .chat-input-area {
    display: flex;
    gap: 10px;
    background: #1a1a1a;
    border-top: 2px solid rgba(245, 158, 11, 0.3);
  }

  #chatInput {
    flex: 1;
    width: auto;
    height: 44px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(245, 158, 11, 0.3);
    color: #f4f4f5;
  }

  #chatInput:focus {
    border-color: #f59e0b;
  }

  #sendBtn {
    width: auto;
    padding: 0 20px;
    background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
    height: 44px;
  }

  #sendBtn:active {
    transform: scale(0.95);
  }
}

@media (max-width: 480px) {
  .mobile-title {
    font-size: 14px;
  }

  .mobile-logo {
    width: 32px;
    height: 32px;
    font-size: 16px;
  }

  .mobile-room-badge {
    font-size: 10px;
    padding: 4px 10px;
  }
}
</style>
</head>
<body>
<!-- DESKTOP HEADER -->
<header>
  <div class="header-container">
    <div class="header-top">
      <div class="brand">
        <div class="logo">🎬</div>
        <div class="brand-text">
          <h1 class="brand-title">WatchVideosTogether.js</h1>
          <div class="brand-subtitle">Made With Love <3</div>
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

<!-- MOBILE HEADER -->
<div class="mobile-header">
  <div class="mobile-header-top">
    <div class="mobile-brand">
      <div class="mobile-logo">🎬</div>
      <h1 class="mobile-title">Watch Together</h1>
    </div>
    <div class="mobile-room-badge" id="mobileRoomId"></div>
    <button class="mobile-menu-btn" id="mobileMenuBtn">⚙️</button>
  </div>
  <div class="mobile-user-badge">
    You are: <span id="mobileUsername">${username}</span>
  </div>
</div>

<!-- MOBILE TABS -->
<div class="mobile-tabs">
  <button class="mobile-tab active" data-tab="video">📺 Video</button>
  <button class="mobile-tab" data-tab="chat">💬 Chat</button>
</div>

<!-- MOBILE CONTROLS DRAWER -->
<div class="mobile-controls-drawer" id="mobileDrawer">
  <div class="drawer-header">
    <div class="drawer-title">⚙️ Controls</div>
    <button class="drawer-close" id="drawerClose">×</button>
  </div>
  
  <div class="drawer-section">
    <div class="drawer-section-label">🎥 Load Video</div>
    <div class="drawer-input-group">
      <input type="text" class="drawer-input" id="mobileVideoUrl" placeholder="Enter video URL">
      <button class="drawer-btn" id="mobileLoadBtn">▶ Load Video</button>
    </div>
  </div>
  
  <div class="drawer-section">
    <div class="drawer-section-label">📤 Upload Video</div>
    <div class="drawer-input-group">
      <input type="password" class="drawer-input" id="mobileAdminKey" placeholder="Admin Key">
      <label for="mobileUploadInput" class="drawer-file-label">
        <span>📁</span>
        <span id="mobileFileName">Choose File</span>
      </label>
      <input type="file" id="mobileUploadInput" accept="video/*" style="display:none">
      <button class="drawer-btn" id="mobileUploadBtn">⬆ Upload Video</button>
    </div>
  </div>
</div>

<div class="main-content">
  <div class="video-section active">
    <video id="player" controls muted playsinline></video>
    <div class="player-controls">
      <div class="speed-control">
        <span class="speed-label">⚡ Speed:</span>
        <input type="range" id="speedSlider" class="speed-slider" min="0.25" max="3" step="0.25" value="1">
        <span class="speed-value" id="speedValue">1×</span>
      </div>
      <button id="unmuteBtn">🔇 Click to Enable Sound</button>
    </div>
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
document.getElementById("mobileRoomId").textContent = room;
document.getElementById("mobileUsername").textContent = "${username}";

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
const speedSlider = document.getElementById("speedSlider");
const speedValue = document.getElementById("speedValue");

// Mobile elements
const mobileMenuBtn = document.getElementById("mobileMenuBtn");
const mobileDrawer = document.getElementById("mobileDrawer");
const drawerClose = document.getElementById("drawerClose");
const mobileVideoUrl = document.getElementById("mobileVideoUrl");
const mobileLoadBtn = document.getElementById("mobileLoadBtn");
const mobileAdminKey = document.getElementById("mobileAdminKey");
const mobileUploadInput = document.getElementById("mobileUploadInput");
const mobileUploadBtn = document.getElementById("mobileUploadBtn");
const mobileFileName = document.getElementById("mobileFileName");
const mobileTabs = document.querySelectorAll(".mobile-tab");
const videoSection = document.querySelector(".video-section");
const chatSection = document.querySelector(".chat-section");

let ignore = false;
let currentSource = "";
let seekTimeout = null;
let isSeeking = false;

const myUsername = "${username}";

// Mobile tab switching
mobileTabs.forEach(tab => {
  tab.addEventListener("click", () => {
    const tabName = tab.dataset.tab;
    mobileTabs.forEach(t => t.classList.remove("active"));
    tab.classList.add("active");
    
    if (tabName === "video") {
      videoSection.classList.add("active");
      chatSection.classList.remove("active");
    } else {
      videoSection.classList.remove("active");
      chatSection.classList.add("active");
    }
  });
});

// Mobile drawer
mobileMenuBtn.addEventListener("click", () => {
  mobileDrawer.classList.add("active");
});

drawerClose.addEventListener("click", () => {
  mobileDrawer.classList.remove("active");
});

mobileDrawer.addEventListener("click", (e) => {
  if (e.target === mobileDrawer) {
    mobileDrawer.classList.remove("active");
  }
});

// Mobile controls
mobileLoadBtn.addEventListener("click", () => {
  const url = mobileVideoUrl.value.trim();
  if (url) {
    socket.emit("video:load", { room, url });
    mobileDrawer.classList.remove("active");
  }
});

mobileUploadInput.addEventListener("change", (e) => {
  if (e.target.files[0]) {
    const fileName = e.target.files[0].name;
    mobileFileName.textContent = fileName.length > 25 ? fileName.substring(0, 25) + '...' : fileName;
  }
});

mobileUploadBtn.addEventListener("click", async () => {
  const file = mobileUploadInput.files[0];
  const key = mobileAdminKey.value.trim();
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

  player.src = videoPath;
  player.load();
  player.onloadedmetadata = () => {
    currentSource = videoPath;
    socket.emit("video:load", { room, url: videoPath });
  };
  
  mobileDrawer.classList.remove("active");
});

// Speed control
speedSlider.addEventListener('input', (e) => {
  const speed = parseFloat(e.target.value);
  speedValue.textContent = speed + '×';
  if (!ignore) {
    player.playbackRate = speed;
    socket.emit("video:speed", { room, speed });
  }
});

// Desktop file upload
uploadInput.onchange = (e) => {
  const label = document.querySelector('.file-upload-btn');
  if (e.target.files[0]) {
    const fileName = e.target.files[0].name;
    label.innerHTML = \`<span>📁</span> \${fileName.length > 20 ? fileName.substring(0, 20) + '...' : fileName}\`;
  }
};

// Unmute
unmuteBtn.onclick = () => {
  player.muted = false;
  unmuteBtn.style.display = "none";
};

player.onvolumechange = () => {
  if (!player.muted) unmuteBtn.style.display = "none";
};

// VIDEO SYNC
socket.emit("join", { room, username: myUsername });
socket.on("video:state", applyState);
socket.on("video:update", applyState);
socket.on("video:speed", (data) => {
  if (!data || ignore) return;
  ignore = true;
  player.playbackRate = data.speed;
  speedSlider.value = data.speed;
  speedValue.textContent = data.speed + '×';
  ignore = false;
});

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
      if (s.playbackRate) {
        player.playbackRate = s.playbackRate;
        speedSlider.value = s.playbackRate;
        speedValue.textContent = s.playbackRate + '×';
      }
      if (s.isPlaying) player.play().catch(() => {});
    };
  } else {
    if (Math.abs(player.currentTime - (s.currentTime || 0)) > 0.5)
      player.currentTime = s.currentTime || 0;
    if (s.playbackRate && Math.abs(player.playbackRate - s.playbackRate) > 0.01) {
      player.playbackRate = s.playbackRate;
      speedSlider.value = s.playbackRate;
      speedValue.textContent = s.playbackRate + '×';
    }
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

  player.src = videoPath;
  player.load();
  player.onloadedmetadata = () => {
    currentSource = videoPath;
    socket.emit("video:load", { room, url: videoPath });
  };
};

// CHAT
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
    
    if (!rooms.has(room)) {
      rooms.set(room, { 
        videoUrl: "", 
        isPlaying: false, 
        currentTime: 0,
        playbackRate: 1,
        chatHistory: []
      });
    }
    
    const roomData = rooms.get(room);
    
    socket.emit("video:state", {
      videoUrl: roomData.videoUrl,
      isPlaying: roomData.isPlaying,
      currentTime: roomData.currentTime,
      playbackRate: roomData.playbackRate
    });
    
    socket.emit("chat:history", roomData.chatHistory);
    
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

  socket.on("video:speed", ({ room, speed }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.playbackRate = speed;
    socket.to(room).emit("video:speed", { speed });
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
