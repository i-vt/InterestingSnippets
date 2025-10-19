// npm init -y
// npm i express socket.io multer
// node SharedTextEditorAndFileshare.js

// Live shared text + file upload/delete + dark/light theme with cookie preference
// Run: npm init -y && npm i express socket.io multer && node server.js

const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const multer = require("multer");
const fs = require("fs");
const path = require("path");

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// ---- File uploads setup ----
const UPLOADS_DIR = path.join(__dirname, "uploads");
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);

const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, UPLOADS_DIR),
  filename: (_, file, cb) => {
    const unique = Date.now() + "-" + Math.round(Math.random() * 1e6);
    cb(null, unique + "-" + file.originalname);
  },
});
const upload = multer({ storage });

// ---- In-memory shared state ----
const rooms = new Map(); // roomId -> { text, files: [] }

// ---- Serve uploads statically ----
app.use("/uploads", express.static(UPLOADS_DIR));

// ---- File upload handler ----
app.post("/upload/:room", upload.single("file"), (req, res) => {
  const { room } = req.params;
  if (!req.file) return res.status(400).send("No file uploaded");

  const fileInfo = {
    id: req.file.filename,
    name: req.file.originalname,
    size: req.file.size,
    url: `/uploads/${req.file.filename}`,
    uploadedAt: Date.now(),
  };

  const roomState = rooms.get(room) || { text: "", files: [] };
  roomState.files.push(fileInfo);
  rooms.set(room, roomState);
  io.to(room).emit("files:update", roomState.files);

  res.json(fileInfo);
});

// ---- File delete handler ----
app.delete("/delete/:room/:fileId", (req, res) => {
  const { room, fileId } = req.params;
  const roomState = rooms.get(room);
  if (!roomState) return res.status(404).send("Room not found");

  const fileIndex = roomState.files.findIndex((f) => f.id === fileId);
  if (fileIndex === -1) return res.status(404).send("File not found");

  const [file] = roomState.files.splice(fileIndex, 1);
  const filePath = path.join(UPLOADS_DIR, file.id);
  if (fs.existsSync(filePath)) fs.unlinkSync(filePath);

  io.to(room).emit("files:update", roomState.files);
  res.sendStatus(200);
});

// ---- Serve client ----
app.get("/", (_, res) => {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(`<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Live Shared Text + Files</title>
<meta name="viewport" content="width=device-width, initial-scale=1">

<style>
:root {
  color-scheme: light dark;
  --bg-light: #fafafa;
  --bg-dark: #121212;
  --text-light: #111;
  --text-dark: #f0f0f0;
  --border-light: #ccc;
  --border-dark: #444;
}
body {
  font-family: system-ui, sans-serif;
  margin: 0;
  transition: background 0.2s, color 0.2s;
}
header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 8px 16px; border-bottom: 1px solid var(--border);
}
main { padding: 16px; }
textarea {
  width: 100%; height: 40vh;
  padding: 8px; box-sizing: border-box; resize: none;
  border-radius: 8px; border: 1px solid var(--border);
  background: var(--bg2); color: inherit;
}
#fileList { list-style: none; padding: 0; margin-top: 10px; }
#fileList li { display: flex; align-items: center; gap: 8px; border-bottom: 1px solid var(--border); padding: 4px 0; }
button { padding: 4px 8px; cursor: pointer; border-radius: 6px; }
input[type=file] { display: none; }
label.upload-btn {
  border: 1px solid var(--border);
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
}
body.light {
  background: var(--bg-light);
  color: var(--text-light);
  --border: var(--border-light);
  --bg2: #fff;
}
body.dark {
  background: var(--bg-dark);
  color: var(--text-dark);
  --border: var(--border-dark);
  --bg2: #1e1e1e;
}
.theme-toggle {
  padding: 6px 10px; border-radius: 6px; border: 1px solid var(--border);
  background: transparent;
}
</style>
</head>
<body>
  <header>
    <div>📝 Live Shared Text & Files</div>
    <div style="display:flex; align-items:center; gap:8px;">
      <label class="upload-btn" for="fileInput">📤 Upload File</label>
      <input id="fileInput" type="file">
      <button id="themeBtn" class="theme-toggle">🌙 Dark</button>
    </div>
  </header>

  <main>
    <textarea id="editor" placeholder="Shared text area..."></textarea>
    <h3>📁 Shared Files</h3>
    <ul id="fileList"></ul>
  </main>

<script src="/socket.io/socket.io.js"></script>
<script>
const room = new URLSearchParams(location.search).get("room") || "main";
const editor = document.getElementById("editor");
const fileInput = document.getElementById("fileInput");
const fileList = document.getElementById("fileList");
const themeBtn = document.getElementById("themeBtn");

// --- Socket ---
const socket = io({ transports: ["websocket", "polling"] });

// --- Text sync ---
socket.on("connect", () => socket.emit("join", { room }));
socket.on("text:sync", ({ text }) => editor.value = text);
editor.addEventListener("input", () => socket.emit("text:update", { room, text: editor.value }));

// --- Files sync ---
socket.on("files:update", renderFiles);
function renderFiles(files = []) {
  fileList.innerHTML = "";
  files.forEach(f => {
    const li = document.createElement("li");
    li.innerHTML = \`
      <a href="\${f.url}" target="_blank">\${f.name}</a>
      (\${(f.size/1024).toFixed(1)} KB)
      <button data-id="\${f.id}" class="delBtn">🗑️</button>
    \`;
    fileList.appendChild(li);
  });
  fileList.querySelectorAll(".delBtn").forEach(btn => {
    btn.onclick = async () => {
      await fetch("/delete/" + room + "/" + btn.dataset.id, { method: "DELETE" });
    };
  });
}

// --- Upload ---
fileInput.addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  const form = new FormData();
  form.append("file", file);
  await fetch("/upload/" + room, { method: "POST", body: form });
  fileInput.value = "";
});

// --- THEME LOGIC ---
function setTheme(theme) {
  document.body.classList.remove("dark", "light");
  document.body.classList.add(theme);
  document.cookie = "theme=" + theme + "; path=/; max-age=31536000";
  themeBtn.textContent = theme === "dark" ? "🌙 Dark" : "☀️ Light";
}

function getCookie(name) {
  const match = document.cookie.match(new RegExp('(^| )' + name + '=([^;]+)'));
  return match ? match[2] : null;
}

function loadTheme() {
  const saved = getCookie("theme");
  setTheme(saved || "dark"); // default dark
}

themeBtn.addEventListener("click", () => {
  const current = document.body.classList.contains("dark") ? "dark" : "light";
  const next = current === "dark" ? "light" : "dark";
  setTheme(next);
});

loadTheme();
</script>
</body>
</html>`);
});

// ---- Socket logic ----
io.on("connection", (socket) => {
  socket.on("join", ({ room }) => {
    socket.join(room);
    const state = rooms.get(room) || { text: "", files: [] };
    rooms.set(room, state);
    socket.emit("text:sync", { text: state.text });
    socket.emit("files:update", state.files);
  });

  socket.on("text:update", ({ room, text }) => {
    const state = rooms.get(room) || { text: "", files: [] };
    state.text = text;
    rooms.set(room, state);
    socket.to(room).emit("text:sync", { text });
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log("Server running at http://localhost:" + PORT));
