#!/bin/bash
set -e

# -----------------------------
# CONFIGURATION
# -----------------------------
DB_NAME="sample_app"
DB_USER="superuser"
DB_PASS="StrongPassword123!"
APP_DIR="/var/www/html"
TEST_URL="http://localhost/index.php"

# -----------------------------
# DATABASE SETUP
# -----------------------------
echo "🗄️ Creating MySQL database and table for test app..."
mysql -u$DB_USER -p$DB_PASS -hlocalhost <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
USE ${DB_NAME};

CREATE TABLE IF NOT EXISTS posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# -----------------------------
# PHP APPLICATION DEPLOYMENT
# -----------------------------
echo "🚀 Deploying simple PHP-MySQL blog app..."

cat <<'EOF' | sudo tee ${APP_DIR}/index.php > /dev/null
<?php
// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);

// DB connection
$mysqli = new mysqli("localhost", "superuser", "StrongPassword123!", "sample_app");

if ($mysqli->connect_errno) {
    die("Connection failed: " . $mysqli->connect_error);
}

// Handle form submission
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $title = $_POST['title'] ?? '';
    $content = $_POST['content'] ?? '';

    if ($stmt = $mysqli->prepare("INSERT INTO posts (title, content) VALUES (?, ?)")) {
        $stmt->bind_param("ss", $title, $content);
        $stmt->execute();
        $stmt->close();
        header("Location: /index.php"); // ✅ Explicit redirect to index.php
        exit;
    } else {
        die("Prepare failed: " . $mysqli->error);
    }
}

// Fetch posts
$result = $mysqli->query("SELECT * FROM posts ORDER BY created_at DESC");
?>

<h1>Simple Blog</h1>

<form method="POST">
    <input name="title" placeholder="Title" required><br><br>
    <textarea name="content" placeholder="Content" required></textarea><br><br>
    <button type="submit">Post</button>
</form>

<hr>

<?php while ($row = $result->fetch_assoc()): ?>
    <h3><?= htmlspecialchars($row['title']) ?></h3>
    <p><?= nl2br(htmlspecialchars($row['content'])) ?></p>
    <small><?= $row['created_at'] ?></small>
    <hr>
<?php endwhile; ?>
EOF

# -----------------------------
# PERMISSIONS & RESTART
# -----------------------------
echo "🔐 Setting permissions..."
sudo chown -R www-data:www-data ${APP_DIR}
sudo chmod -R 755 ${APP_DIR}
sudo systemctl restart apache2

echo "✅ Application deployed at ${TEST_URL}"

# -----------------------------
# LOAD TESTING
# -----------------------------
echo "🧪 Installing Apache Bench for load testing..."
sudo apt-get install -y apache2-utils

echo "⚙️ Running Apache Bench (1000 requests, 100 concurrency)..."
ab -n 1000 -c 100 ${TEST_URL}

echo "📊 Load test complete! Monitor your server with 'top' or 'htop'."

# -----------------------------
# END
# -----------------------------
echo "🏁 App deployment and testing complete!"
echo "Visit: http://<server>/index.php"
