#!/usr/bin/env node
/**
 * Video Resize Tool — single-file Node.js port of the Spring Boot app.
 *
 * Dependencies: express, multer
 *   npm install express multer
 *
 * Requires ffmpeg to be installed and on PATH.
 * Run: node server.js
 */

const express = require("express");
const multer  = require("multer");
const path    = require("path");
const fs      = require("fs");
const { spawn } = require("child_process");
const { randomUUID } = require("crypto");

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PORT          = process.env.PORT || 8080;
const UPLOAD_DIR    = path.join(__dirname, "uploaded-videos");
const MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024; // 2 GB

// Ensure upload directory exists
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
const app = express();

// Multer — store files with a UUID-based name, preserve original extension
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename:    (_req, file, cb) => {
    const ext      = path.extname(file.originalname);
    const safeName = randomUUID() + (ext ? ext : "");
    cb(null, safeName);
  },
});
const upload = multer({ storage, limits: { fileSize: MAX_FILE_SIZE } });

// ---------------------------------------------------------------------------
// HTML template (replaces index.html / Thymeleaf)
// ---------------------------------------------------------------------------
function renderPage({ message = "", downloadLink = "", filename = "" } = {}) {
  const messageHtml = message
    ? `<p class="msg">${escHtml(message)}</p>`
    : "";

  const downloadHtml = downloadLink
    ? `<a class="download-btn" href="${escHtml(downloadLink)}">⬇ Download ${escHtml(filename)}</a>`
    : "";

  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Video Resize Tool</title>
  <style>
    body { font-family: sans-serif; max-width: 520px; margin: 60px auto; padding: 0 16px; }
    h1   { font-size: 1.5rem; margin-bottom: 24px; }
    input[type=file] { display: block; margin-bottom: 12px; }
    button { padding: 8px 20px; cursor: pointer; }
    .msg  { margin-top: 20px; color: #333; }
    .download-btn {
      display: inline-block; margin-top: 16px; padding: 10px 20px;
      background: #0070f3; color: #fff; text-decoration: none; border-radius: 6px;
    }
    .download-btn:hover { background: #005bb5; }
  </style>
</head>
<body>
  <h1>Upload Video for Resizing</h1>
  <form method="POST" action="/upload" enctype="multipart/form-data">
    <input type="file" name="file" required>
    <button type="submit">Upload &amp; Resize</button>
  </form>
  ${messageHtml}
  ${downloadHtml}
</body>
</html>`;
}

function escHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// GET /
app.get("/", (req, res) => {
  // Pull one-time flash values from query string (we use a simple redirect
  // with encoded params instead of a session store to stay dependency-free)
  const { message, downloadLink, filename } = req.query;
  res.send(renderPage({ message, downloadLink, filename }));
});

// POST /upload
app.post("/upload", upload.single("file"), async (req, res) => {
  const redirect = (params) => {
    const qs = new URLSearchParams(params).toString();
    res.redirect(`/?${qs}`);
  };

  if (!req.file) {
    return redirect({ message: "Please select a file to upload." });
  }

  const savedName = req.file.filename;

  try {
    const outputName = await resizeVideo(savedName);
    redirect({
      message:      `Successfully uploaded and resized '${savedName}'`,
      downloadLink: `/videos/${outputName}`,
      filename:     outputName,
    });
  } catch (err) {
    console.error("Resize error:", err);
    redirect({ message: `Failed to resize file: ${escHtml(savedName)}` });
  }
});

// GET /videos/:filename  — serves / forces download of the resized file
app.get("/videos/:filename", (req, res) => {
  // Basic path-traversal guard
  const filename = path.basename(req.params.filename);
  const filePath = path.join(UPLOAD_DIR, filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).send("File not found.");
  }

  res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
  res.setHeader("Content-Type", "application/octet-stream");
  res.sendFile(filePath);
});

// ---------------------------------------------------------------------------
// ffmpeg helper
// ---------------------------------------------------------------------------
function resizeVideo(filename) {
  return new Promise((resolve, reject) => {
    const inputPath  = path.join(UPLOAD_DIR, filename);
    const outputName = `resized-${filename}`;
    const outputPath = path.join(UPLOAD_DIR, outputName);

    const proc = spawn(
      "ffmpeg",
      ["-i", inputPath, "-vf", "scale=-2:360", outputPath],
      { stdio: "inherit" }   // mirrors processBuilder.inheritIO()
    );

    proc.on("close", (code) => {
      if (code === 0) resolve(outputName);
      else reject(new Error(`ffmpeg exited with code ${code}`));
    });

    proc.on("error", (err) => {
      reject(new Error(`Failed to start ffmpeg: ${err.message}`));
    });
  });
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`Video Resize Tool running → http://localhost:${PORT}`);
});
