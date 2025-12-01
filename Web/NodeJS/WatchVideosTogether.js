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

// === CRITICAL: Configure server timeouts for large file uploads ===
server.timeout = 0; // Disable timeout (or set to very large value like 2 * 60 * 60 * 1000 for 2 hours)
server.keepAliveTimeout = 0; // Disable keep-alive timeout
server.headersTimeout = 0; // Disable headers timeout
server.requestTimeout = 0; // Disable request timeout (Node.js 18+)

// === SETUP ===
const UPLOADS_DIR = path.join(__dirname, "uploads");
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);
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

// Function to generate a color hash from username
function getUserColor(username) {
  let hash = 0;
  for (let i = 0; i < username.length; i++) {
    hash = username.charCodeAt(i) + ((hash << 5) - hash);
  }
  const hue = hash % 360;
  return `hsl(${hue}, 70%, 60%)`;
}

// === Multer (video uploads) - CONFIGURED FOR LARGE FILES ===
const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, UPLOADS_DIR),
  filename: (_, file, cb) => {
    const ext = path.extname(file.originalname) || ".mp4";
    cb(null, uuidv4() + ext);
  },
});

// Configure multer with larger limits for multi-GB files
const upload = multer({ 
  storage,
  limits: {
    fileSize: 10 * 1024 * 1024 * 1024, // 10GB limit (adjust as needed)
  }
});

// === In-memory shared rooms ===
const rooms = new Map();

// === Session management (max 1000 sessions) ===
const sessions = new Map(); // sessionId -> username
const MAX_SESSIONS = 1000;

// === Upload route - WITH COMPREHENSIVE TIMEOUT AND ERROR HANDLING ===
app.post("/upload", (req, res, next) => {
  console.log("ðŸ“¥ Upload started - Setting timeouts...");
  
  // Set VERY long timeouts for large file uploads (4 hours)
  const UPLOAD_TIMEOUT = 4 * 60 * 60 * 1000;
  
  req.setTimeout(UPLOAD_TIMEOUT, () => {
    console.error("âŒ Request timeout after", UPLOAD_TIMEOUT / 1000, "seconds");
  });
  
  res.setTimeout(UPLOAD_TIMEOUT, () => {
    console.error("âŒ Response timeout after", UPLOAD_TIMEOUT / 1000, "seconds");
  });
  
  // Socket timeout
  if (req.socket) {
    req.socket.setTimeout(UPLOAD_TIMEOUT, () => {
      console.error("âŒ Socket timeout after", UPLOAD_TIMEOUT / 1000, "seconds");
    });
  }
  
  // Connection monitoring
  req.on('close', () => {
    console.log("âš ï¸  Request connection closed");
  });
  
  req.on('aborted', () => {
    console.error("âŒ Request aborted by client");
  });
  
  req.on('error', (err) => {
    console.error("âŒ Request error:", err);
  });
  
  // Track upload progress
  let receivedBytes = 0;
  req.on('data', (chunk) => {
    receivedBytes += chunk.length;
    if (receivedBytes % (50 * 1024 * 1024) === 0) { // Log every 50MB
      console.log(`ðŸ“Š Received ${(receivedBytes / 1024 / 1024).toFixed(2)} MB...`);
    }
  });
  
  next();
}, upload.single("video"), (req, res) => {
  if (req.query.key !== ADMIN_KEY) {
    console.error("âŒ Invalid admin key provided");
    return res.status(403).send("âŒ Invalid admin key");
  }
  
  if (!req.file) {
    console.error("âŒ No file in request");
    return res.status(400).send("âŒ No video file uploaded");
  }

  const filePath = path.join(UPLOADS_DIR, req.file.filename);
  if (!fs.existsSync(filePath)) {
    console.error("ðŸš« File missing right after upload:", filePath);
    return res.status(500).send("Internal error saving file");
  }

  const fileUrl = `/uploads/${req.file.filename}`;
  console.log("âœ… Upload complete:", fileUrl, `(${(req.file.size / 1024 / 1024).toFixed(2)} MB)`);
  res.json({ url: fileUrl });
}, (err, req, res, next) => {
  // Error handler for multer
  console.error("âŒ Multer/Upload error:", err.message);
  console.error("Error details:", err);
  
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).send('File too large');
  }
  
  res.status(500).send('Upload error: ' + err.message);
});

// === Video streaming with FIXED Range support ===
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
      "Accept-Ranges": "bytes",
    });
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  // Parse range header
  const parts = range.replace(/bytes=/, "").split("-");
  const start = parseInt(parts[0], 10);
  const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

  // FIXED: Proper range validation
  if (isNaN(start) || isNaN(end) || start < 0 || end >= fileSize || start > end) {
    console.error(`Invalid range request: ${range} for file size ${fileSize}`);
    res.writeHead(416, { 
      "Content-Range": `bytes */${fileSize}`,
      "Content-Type": mimeType
    });
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
    if (!res.headersSent) {
      res.status(500).end();
    } else {
      res.end();
    }
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
<title>WatchVideosTogether.js</title>
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
  overflow: hidden;
}

/* ===== ENTERPRISE HEADER - MOBILE FIRST ===== */
header {
  background: linear-gradient(135deg, #1e1e22 0%, #121214 100%);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 2px 16px rgba(0, 0, 0, 0.4);
  flex-shrink: 0;
  position: relative;
  z-index: 100;
}

.header-container {
  max-width: 1600px;
  margin: 0 auto;
}

.header-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  background: rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(10px);
}

.brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.logo {
  width: 36px;
  height: 36px;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
  flex-shrink: 0;
}

.brand-text {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.brand-title {
  font-size: 15px;
  font-weight: 600;
  color: #f4f4f5;
  margin: 0;
  letter-spacing: -0.02em;
  white-space: nowrap;
}

.brand-subtitle {
  font-size: 10px;
  color: #71717a;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  white-space: nowrap;
}

.room-info {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: rgba(59, 130, 246, 0.12);
  border-radius: 8px;
  border: 1px solid rgba(59, 130, 246, 0.3);
  backdrop-filter: blur(8px);
}

.room-label {
  font-size: 10px;
  color: #a1a1aa;
  font-weight: 500;
  display: none;
}

.room-id {
  font-family: 'SF Mono', 'Courier New', monospace;
  color: #60a5fa;
  font-weight: 600;
  font-size: 12px;
  letter-spacing: 0.05em;
}

/* Mobile Tabs Navigation */
.mobile-tabs {
  display: flex;
  background: rgba(0, 0, 0, 0.4);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

.mobile-tab {
  flex: 1;
  padding: 14px 16px;
  text-align: center;
  font-size: 13px;
  font-weight: 600;
  color: #71717a;
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all 0.2s ease;
  border-bottom: 2px solid transparent;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}

.mobile-tab.active {
  color: #3b82f6;
  background: rgba(59, 130, 246, 0.08);
  border-bottom-color: #3b82f6;
}

.mobile-tab:active {
  transform: scale(0.98);
}

.controls-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 10px 16px;
  background: rgba(59, 130, 246, 0.1);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 8px;
  color: #60a5fa;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  white-space: nowrap;
  user-select: none;
}

.controls-toggle:hover {
  background: rgba(59, 130, 246, 0.15);
  border-color: rgba(59, 130, 246, 0.4);
}

.controls-toggle:active {
  transform: scale(0.97);
}

.controls-toggle.expanded {
  background: rgba(59, 130, 246, 0.2);
  border-color: rgba(59, 130, 246, 0.5);
}

/* Header Controls Section */
.header-controls {
  max-height: 0;
  overflow: hidden;
  opacity: 0;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  background: rgba(0, 0, 0, 0.3);
  border-top: 1px solid transparent;
}

.header-controls.expanded {
  max-height: 600px;
  opacity: 1;
  border-top-color: rgba(255, 255, 255, 0.05);
}

.controls-inner {
  padding: 20px 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* Upload Progress */
.upload-progress {
  display: none;
  margin-top: 10px;
  padding: 10px;
  background: rgba(59, 130, 246, 0.1);
  border-radius: 8px;
  border: 1px solid rgba(59, 130, 246, 0.2);
}

.progress-bar {
  width: 100%;
  height: 6px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 3px;
  overflow: hidden;
  margin-bottom: 6px;
}

.progress-fill {
  height: 100%;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  width: 0%;
  transition: width 0.3s ease;
}

.progress-text {
  font-size: 11px;
  color: #a1a1aa;
  text-align: center;
}

/* Participants Section */
.participants-section {
  background: rgba(0, 0, 0, 0.3);
  border-radius: 10px;
  padding: 12px;
  border: 1px solid rgba(255, 255, 255, 0.05);
}

.participants-header {
  font-size: 11px;
  font-weight: 600;
  color: #a1a1aa;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 10px;
  display: flex;
  align-items: center;
  gap: 6px;
}

.participant-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 20px;
  height: 20px;
  padding: 0 6px;
  background: rgba(59, 130, 246, 0.2);
  border-radius: 10px;
  font-size: 11px;
  font-weight: 700;
  color: #60a5fa;
}

.participants-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.participant {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  transition: all 0.2s ease;
}

.participant:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.12);
  transform: translateY(-1px);
}

.participant-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 13px;
  color: white;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
  flex-shrink: 0;
  border: 2px solid rgba(255, 255, 255, 0.2);
}

.participant-name {
  font-size: 13px;
  font-weight: 600;
  color: #e4e4e7;
  letter-spacing: 0.01em;
}

.participant.me {
  background: rgba(59, 130, 246, 0.15);
  border-color: rgba(59, 130, 246, 0.3);
}

.participant.me .participant-name::after {
  content: " (You)";
  font-weight: 400;
  color: #60a5fa;
  font-size: 11px;
}

/* Control Group Styling */
.control-group {
  background: rgba(0, 0, 0, 0.3);
  border-radius: 10px;
  padding: 14px;
  border: 1px solid rgba(255, 255, 255, 0.05);
}

.control-label {
  font-size: 11px;
  font-weight: 600;
  color: #a1a1aa;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 10px;
  display: block;
}

.input-group {
  display: flex;
  gap: 8px;
  margin-bottom: 10px;
}

.input-group:last-child {
  margin-bottom: 0;
}

input[type="text"],
input[type="file"] {
  flex: 1;
  padding: 10px 12px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 8px;
  color: #e4e4e7;
  font-size: 13px;
  transition: all 0.2s ease;
}

input[type="text"]:focus,
input[type="file"]:focus {
  outline: none;
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(59, 130, 246, 0.5);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

input[type="text"]::placeholder {
  color: #71717a;
}

button {
  padding: 10px 16px;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  border: none;
  border-radius: 8px;
  color: white;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  white-space: nowrap;
  letter-spacing: 0.02em;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
}

button:hover {
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

button:active {
  transform: translateY(0);
  box-shadow: 0 1px 4px rgba(59, 130, 246, 0.3);
}

button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  transform: none;
}

/* Speed Control */
.speed-control {
  display: flex;
  align-items: center;
  gap: 12px;
}

.speed-control label {
  font-size: 12px;
  color: #a1a1aa;
  font-weight: 500;
  min-width: 35px;
}

input[type="range"] {
  flex: 1;
  height: 6px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 3px;
  outline: none;
  -webkit-appearance: none;
}

input[type="range"]::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 18px;
  height: 18px;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  border-radius: 50%;
  cursor: pointer;
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.4);
  transition: all 0.2s ease;
}

input[type="range"]::-webkit-slider-thumb:hover {
  transform: scale(1.15);
  box-shadow: 0 3px 10px rgba(59, 130, 246, 0.5);
}

input[type="range"]::-moz-range-thumb {
  width: 18px;
  height: 18px;
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  border-radius: 50%;
  cursor: pointer;
  border: none;
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.4);
  transition: all 0.2s ease;
}

input[type="range"]::-moz-range-thumb:hover {
  transform: scale(1.15);
  box-shadow: 0 3px 10px rgba(59, 130, 246, 0.5);
}

/* Sound Toggle */
.sound-toggle {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.1);
  cursor: pointer;
  transition: all 0.2s ease;
  user-select: none;
}

.sound-toggle:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.15);
}

.sound-toggle:active {
  transform: scale(0.97);
}

.sound-toggle.muted {
  background: rgba(239, 68, 68, 0.15);
  border-color: rgba(239, 68, 68, 0.3);
}

.sound-toggle.unmuted {
  background: rgba(34, 197, 94, 0.15);
  border-color: rgba(34, 197, 94, 0.3);
}

.sound-icon {
  font-size: 18px;
  line-height: 1;
}

.sound-label {
  font-size: 12px;
  font-weight: 600;
  color: #e4e4e7;
  letter-spacing: 0.02em;
}

/* ===== DESKTOP LAYOUT (min-width: 768px) ===== */
@media (min-width: 768px) {
  .mobile-tabs { 
    display: none; 
  }
  
  .room-label {
    display: inline;
  }
  
  .brand-title {
    font-size: 18px;
  }
  
  .brand-subtitle {
    font-size: 11px;
  }
  
  .logo {
    width: 42px;
    height: 42px;
    font-size: 20px;
  }
  
  /* Keep toggle button visible on desktop */
  .controls-toggle {
    display: flex;
  }
  
  /* Controls can still be expanded/collapsed on desktop */
  .header-controls.expanded {
    max-height: 800px;
  }
  
  .controls-inner {
    padding: 24px;
    flex-direction: row;
    flex-wrap: wrap;
    gap: 20px;
  }
  
  .participants-section {
    flex: 1 1 100%;
  }
  
  .control-group {
    flex: 1 1 calc(50% - 10px);
    min-width: 280px;
  }
  
  .speed-control {
    flex: 1 1 100%;
  }
}

/* ===== MAIN CONTENT AREA ===== */
.main-content {
  display: flex;
  flex: 1;
  overflow: hidden;
  position: relative;
}

/* Video Container */
#videoContainer {
  flex: 1;
  display: none;
  flex-direction: column;
  background: #000;
  position: relative;
}

#videoContainer.active {
  display: flex;
}

video {
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #000;
}

/* Chat Container */
#chatContainer {
  flex: 1;
  display: none;
  flex-direction: column;
  background: #0f0f11;
  border-left: 1px solid rgba(255, 255, 255, 0.1);
}

#chatContainer.active {
  display: flex;
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.message {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 10px 12px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 8px;
  border-left: 3px solid rgba(59, 130, 246, 0.5);
  animation: slideIn 0.2s ease;
}

@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.message.system {
  background: rgba(168, 85, 247, 0.1);
  border-left-color: rgba(168, 85, 247, 0.5);
  font-style: italic;
}

.username {
  font-size: 12px;
  font-weight: 700;
  color: #60a5fa;
  letter-spacing: 0.02em;
}

.message.system .username {
  color: #c084fc;
}

.text {
  font-size: 14px;
  color: #e4e4e7;
  line-height: 1.5;
  word-wrap: break-word;
}

.chat-input-area {
  padding: 16px;
  background: rgba(0, 0, 0, 0.4);
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
}

.chat-input-group {
  display: flex;
  gap: 8px;
}

#chatInput {
  flex: 1;
  padding: 12px 14px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 10px;
  color: #e4e4e7;
  font-size: 14px;
  transition: all 0.2s ease;
}

#chatInput:focus {
  outline: none;
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(59, 130, 246, 0.5);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

#chatInput::placeholder {
  color: #71717a;
}

#sendBtn {
  padding: 12px 20px;
  font-size: 14px;
}

/* Desktop Layout for Main Content */
@media (min-width: 768px) {
  #videoContainer {
    display: flex;
    flex: 2;
  }
  
  #chatContainer {
    display: flex;
    flex: 1;
    max-width: 400px;
  }
}

/* Custom Scrollbar */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: rgba(255, 255, 255, 0.05);
}

::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.2);
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.3);
}
</style>
</head>
<body>
<header>
  <div class="header-container">
    <div class="header-top">
      <div class="brand">
        <div class="logo">ðŸŽ¬</div>
        <div class="brand-text">
          <div class="brand-title">WatchVideosTogether.js</div>
          <div class="brand-subtitle">Made with Love â¤ï¸</div>
        </div>
      </div>
      <div class="room-info">
        <span class="room-label">Room:</span>
        <span class="room-id" id="roomId"></span>
      </div>
    </div>
    
    <div class="mobile-tabs">
      <button class="mobile-tab active" id="videoTab">ðŸ“¹ Video</button>
      <button class="mobile-tab" id="chatTab">ðŸ’¬ Chat</button>
    </div>
    
    <button class="controls-toggle" id="controlsToggle">
      <span>âš™ï¸</span>
      <span id="toggleText">Show Controls</span>
    </button>
    
    <div class="header-controls" id="headerControls">
      <div class="controls-inner">
        <!-- Participants Section -->
        <div class="participants-section">
          <div class="participants-header">
            ðŸ‘¥ Participants
            <span class="participant-count" id="participantCount">0</span>
          </div>
          <div class="participants-list" id="participantsList">
            <!-- Participants will be added here dynamically -->
          </div>
        </div>
        
        <div class="control-group">
          <label class="control-label">ðŸ”— Load Video URL</label>
          <div class="input-group">
            <input type="text" id="videoUrl" placeholder="https://example.com/video.mp4">
            <button id="loadBtn">Load</button>
          </div>
        </div>
        
        <div class="control-group">
          <label class="control-label">ðŸ“¤ Upload Video (Admin)</label>
          <div class="input-group">
            <input type="text" id="adminKey" placeholder="Admin Key">
          </div>
          <div class="input-group">
            <input type="file" id="uploadInput" accept="video/*">
            <button id="uploadBtn">Upload</button>
          </div>
          <div class="upload-progress" id="uploadProgress">
            <div class="progress-bar">
              <div class="progress-fill" id="progressFill"></div>
            </div>
            <div class="progress-text" id="progressText">Uploading...</div>
          </div>
        </div>
        
        <div class="speed-control">
          <label>Speed:</label>
          <input type="range" id="speedSlider" min="0.25" max="2" step="0.25" value="1">
          <span id="speedValue">1x</span>
        </div>
        
        <div class="sound-toggle" id="soundToggle">
          <span class="sound-icon" id="soundIcon">ðŸ”Š</span>
          <span class="sound-label">Click to toggle sound</span>
        </div>
      </div>
    </div>
  </div>
</header>

<div class="main-content">
  <div id="videoContainer" class="active">
    <video id="player" controls></video>
  </div>
  
  <div id="chatContainer">
    <div class="chat-messages" id="chatMessages"></div>
    <div class="chat-input-area">
      <div class="chat-input-group">
        <input type="text" id="chatInput" placeholder="Type a message...">
        <button id="sendBtn">Send</button>
      </div>
    </div>
  </div>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
const socket = io();
const urlParams = new URLSearchParams(location.search);
const room = urlParams.get("room") || "default";
const myUsername = ${JSON.stringify(username)};

// Display room ID
document.getElementById("roomId").textContent = room;

// UI elements
const player = document.getElementById("player");
const videoUrl = document.getElementById("videoUrl");
const loadBtn = document.getElementById("loadBtn");
const uploadInput = document.getElementById("uploadInput");
const uploadBtn = document.getElementById("uploadBtn");
const adminKey = document.getElementById("adminKey");
const speedSlider = document.getElementById("speedSlider");
const speedValue = document.getElementById("speedValue");
const soundToggle = document.getElementById("soundToggle");
const soundIcon = document.getElementById("soundIcon");
const chatMessages = document.getElementById("chatMessages");
const chatInput = document.getElementById("chatInput");
const sendBtn = document.getElementById("sendBtn");
const participantsList = document.getElementById("participantsList");
const participantCount = document.getElementById("participantCount");
const uploadProgress = document.getElementById("uploadProgress");
const progressFill = document.getElementById("progressFill");
const progressText = document.getElementById("progressText");

// State
let ignore = false;
let isSeeking = false;
let seekTimeout;
let currentSource = "";

// Helper function to toggle controls text
function updateToggleText(isExpanded) {
  const toggleText = document.getElementById('toggleText');
  if (toggleText) {
    toggleText.textContent = isExpanded ? 'Hide Controls' : 'Show Controls';
  }
}

// Sound toggle functionality
function updateSoundToggle() {
  const icon = document.getElementById('soundIcon');
  if (player.muted) {
    icon.textContent = 'ðŸ”‡';
    soundToggle.classList.remove('unmuted');
    soundToggle.classList.add('muted');
  } else {
    icon.textContent = 'ðŸ”Š';
    soundToggle.classList.remove('muted');
    soundToggle.classList.add('unmuted');
  }
}

soundToggle.onclick = () => {
  player.muted = !player.muted;
  updateSoundToggle();
};

// Speed slider handler
speedSlider.oninput = () => {
  const speed = parseFloat(speedSlider.value);
  speedValue.textContent = speed + 'x';
  player.playbackRate = speed;
  socket.emit("video:speed", { room, speed });
};

// Initialize sound toggle state
updateSoundToggle();

// === PARTICIPANTS MANAGEMENT ===
function getUserColor(username) {
  let hash = 0;
  for (let i = 0; i < username.length; i++) {
    hash = username.charCodeAt(i) + ((hash << 5) - hash);
  }
  const hue = hash % 360;
  return "hsl(" + hue + ", 70%, 60%)";
}

function getInitials(username) {
  return username.substring(0, 2).toUpperCase();
}

function updateParticipantsList(participants) {
  participantsList.innerHTML = '';
  participantCount.textContent = participants.length;
  
  participants.forEach(username => {
    const participantEl = document.createElement('div');
    participantEl.className = 'participant' + (username === myUsername ? ' me' : '');
    
    const avatarEl = document.createElement('div');
    avatarEl.className = 'participant-avatar';
    avatarEl.style.backgroundColor = getUserColor(username);
    avatarEl.textContent = getInitials(username);
    
    const nameEl = document.createElement('div');
    nameEl.className = 'participant-name';
    nameEl.textContent = username;
    
    participantEl.appendChild(avatarEl);
    participantEl.appendChild(nameEl);
    participantsList.appendChild(participantEl);
  });
}

// Listen for participant updates
socket.on("participants:update", updateParticipantsList);

// === MOBILE TAB SWITCHING ===
const videoTab = document.getElementById('videoTab');
const chatTab = document.getElementById('chatTab');
const videoContainer = document.getElementById('videoContainer');
const chatContainer = document.getElementById('chatContainer');

if (videoTab && chatTab) {
  videoTab.onclick = () => {
    videoTab.classList.add('active');
    chatTab.classList.remove('active');
    videoContainer.classList.add('active');
    chatContainer.classList.remove('active');
  };

  chatTab.onclick = () => {
    chatTab.classList.add('active');
    videoTab.classList.remove('active');
    chatContainer.classList.add('active');
    videoContainer.classList.remove('active');
  };
}

// === CONTROLS TOGGLE ===
const controlsToggle = document.getElementById('controlsToggle');
const headerControls = document.getElementById('headerControls');

if (controlsToggle) {
  controlsToggle.onclick = () => {
    const isExpanded = headerControls.classList.toggle('expanded');
    controlsToggle.classList.toggle('expanded', isExpanded);
    updateToggleText(isExpanded);
  };
  
  // Keyboard shortcut: 'C' key to toggle controls
  document.addEventListener('keydown', (e) => {
    // Only trigger if not typing in an input field
    if (e.key === 'c' && !e.target.matches('input, textarea')) {
      e.preventDefault();
      const isExpanded = headerControls.classList.toggle('expanded');
      controlsToggle.classList.toggle('expanded', isExpanded);
      updateToggleText(isExpanded);
    }
  });
  
  // Initialize with correct text
  updateToggleText(false);
}

// === VIDEO SYNC ===
socket.emit("join", { room, username: myUsername });
socket.on("video:state", applyState);
socket.on("video:update", applyState);

// Handle speed updates separately to avoid time jumps
socket.on("video:speed-update", (data) => {
  ignore = true;
  player.playbackRate = data.playbackRate;
  speedSlider.value = data.playbackRate;
  speedValue.textContent = data.playbackRate + 'x';
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
      if (s.playbackRate !== undefined) {
        player.playbackRate = s.playbackRate;
        speedSlider.value = s.playbackRate;
        speedValue.textContent = s.playbackRate + 'x';
      }
      if (s.isPlaying) player.play().catch(() => {});
    };
  } else {
    if (Math.abs(player.currentTime - (s.currentTime || 0)) > 0.5)
      player.currentTime = s.currentTime || 0;
    if (s.playbackRate !== undefined && Math.abs(player.playbackRate - s.playbackRate) > 0.01) {
      player.playbackRate = s.playbackRate;
      speedSlider.value = s.playbackRate;
      speedValue.textContent = s.playbackRate + 'x';
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

// FIX: Load video via URL - update local player immediately
loadBtn.onclick = () => {
  const url = videoUrl.value.trim();
  if (!url) return;
  
  // Update local player immediately
  currentSource = url;
  player.src = url;
  player.load();
  player.onloadedmetadata = () => {
    // Now emit to sync with others
    socket.emit("video:load", { room, url });
  };
};

// Upload functionality with progress tracking for large files
uploadBtn.onclick = async () => {
  const file = uploadInput.files[0];
  const key = adminKey.value.trim();
  if (!file || !key) return alert("Enter admin key and select a file.");

  const form = new FormData();
  form.append("video", file);

  // Show progress bar
  uploadProgress.style.display = 'block';
  uploadBtn.disabled = true;
  progressFill.style.width = '0%';
  progressText.textContent = 'Uploading... 0%';

  try {
    const xhr = new XMLHttpRequest();
    
    // CRITICAL: Remove any XHR timeout to allow large uploads
    xhr.timeout = 0;
    
    // Track upload progress
    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) {
        const percentComplete = (e.loaded / e.total) * 100;
        progressFill.style.width = percentComplete + '%';
        progressText.textContent = \`Uploading... \${percentComplete.toFixed(1)}% (\${(e.loaded / 1024 / 1024).toFixed(1)} MB / \${(e.total / 1024 / 1024).toFixed(1)} MB)\`;
      }
    });
    
    xhr.addEventListener('load', () => {
      if (xhr.status === 200) {
        const data = JSON.parse(xhr.responseText);
        const videoPath = data.url;
        console.log("Uploaded:", videoPath);
        
        progressText.textContent = 'Upload complete! Loading video...';
        
        player.src = videoPath;
        player.load();
        player.onloadedmetadata = () => {
          currentSource = videoPath;
          socket.emit("video:load", { room, url: videoPath });
          
          // Hide progress after a delay
          setTimeout(() => {
            uploadProgress.style.display = 'none';
            uploadBtn.disabled = false;
            uploadInput.value = '';
          }, 2000);
        };
      } else {
        alert(xhr.responseText || 'Upload failed');
        uploadProgress.style.display = 'none';
        uploadBtn.disabled = false;
      }
    });
    
    xhr.addEventListener('error', () => {
      alert('Upload failed: Network error');
      uploadProgress.style.display = 'none';
      uploadBtn.disabled = false;
    });
    
    xhr.open('POST', '/upload?key=' + encodeURIComponent(key));
    xhr.send(form);
    
  } catch (error) {
    alert('Upload failed: ' + error.message);
    uploadProgress.style.display = 'none';
    uploadBtn.disabled = false;
  }
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
    socket.username = username;
    socket.currentRoom = room;
    
    // Initialize room if needed
    if (!rooms.has(room)) {
      rooms.set(room, { 
        videoUrl: "", 
        isPlaying: false, 
        currentTime: 0,
        playbackRate: 1,
        chatHistory: [],
        participants: new Set(),
        lastUpdateTime: Date.now()
      });
    }
    
    const roomData = rooms.get(room);
    
    // Add user to participants
    roomData.participants.add(username);
    
    // Calculate current time if video is playing
    let calculatedTime = roomData.currentTime;
    if (roomData.isPlaying && roomData.videoUrl) {
      const elapsedSeconds = (Date.now() - roomData.lastUpdateTime) / 1000;
      calculatedTime = roomData.currentTime + (elapsedSeconds * roomData.playbackRate);
    }
    
    // Send video state with calculated time
    socket.emit("video:state", {
      videoUrl: roomData.videoUrl,
      isPlaying: roomData.isPlaying,
      currentTime: calculatedTime,
      playbackRate: roomData.playbackRate
    });
    
    // Send chat history
    socket.emit("chat:history", roomData.chatHistory);
    
    // Send updated participant list to everyone in the room
    const participantsList = Array.from(roomData.participants);
    io.to(room).emit("participants:update", participantsList);
    
    // Announce user joined
    const joinMsg = {
      username: "System",
      message: username + " joined the room",
      isSystem: true,
      timestamp: Date.now()
    };
    roomData.chatHistory.push(joinMsg);
    if (roomData.chatHistory.length > 100) roomData.chatHistory.shift();
    
    io.to(room).emit("chat:message", joinMsg);
    
    console.log("âœ… " + username + " joined room " + room);
  });
  
  socket.on("disconnect", () => {
    if (socket.currentRoom && socket.username) {
      const roomData = rooms.get(socket.currentRoom);
      if (roomData) {
        // Remove user from participants
        roomData.participants.delete(socket.username);
        
        // Send updated participant list
        const participantsList = Array.from(roomData.participants);
        io.to(socket.currentRoom).emit("participants:update", participantsList);
        
        // Announce user left
        const leaveMsg = {
          username: "System",
          message: socket.username + " left the room",
          isSystem: true,
          timestamp: Date.now()
        };
        roomData.chatHistory.push(leaveMsg);
        if (roomData.chatHistory.length > 100) roomData.chatHistory.shift();
        
        io.to(socket.currentRoom).emit("chat:message", leaveMsg);
        
        console.log("ðŸ‘‹ " + socket.username + " left room " + socket.currentRoom);
        
        // Clean up empty rooms
        if (roomData.participants.size === 0) {
          rooms.delete(socket.currentRoom);
          console.log("ðŸ—‘ï¸  Deleted empty room " + socket.currentRoom);
        }
      }
    }
  });

  socket.on("video:load", ({ room, url }) => {
    const s = rooms.get(room);
    if (!s) return;
    Object.assign(s, { videoUrl: url, currentTime: 0, isPlaying: false, lastUpdateTime: Date.now() });
    io.to(room).emit("video:update", s);
  });

  socket.on("video:play", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.isPlaying = true;
    s.currentTime = time || 0;
    s.lastUpdateTime = Date.now();
    socket.to(room).emit("video:update", s);
  });

  socket.on("video:pause", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.isPlaying = false;
    s.currentTime = time || 0;
    s.lastUpdateTime = Date.now();
    socket.to(room).emit("video:update", s);
  });

  socket.on("video:seek", ({ room, time }) => {
    const s = rooms.get(room);
    if (!s) return;
    s.currentTime = time;
    s.lastUpdateTime = Date.now();
    socket.to(room).emit("video:update", s);
  });

  socket.on("video:speed", ({ room, speed }) => {
    const s = rooms.get(room);
    if (!s) return;
    
    // Calculate current position before changing speed
    if (s.isPlaying && s.videoUrl) {
      const elapsedSeconds = (Date.now() - s.lastUpdateTime) / 1000;
      s.currentTime = s.currentTime + (elapsedSeconds * s.playbackRate);
    }
    
    s.playbackRate = speed;
    s.lastUpdateTime = Date.now();
    
    // Only send playbackRate change, not the full state to avoid time jumps
    socket.to(room).emit("video:speed-update", { playbackRate: speed });
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
  console.log("ðŸš€ Shared Video Player at http://localhost:" + PORT);
  console.log("ðŸ”‘ Admin Upload Key:", ADMIN_KEY);
});
