let faviconToggle = 1;
setInterval(function() {
  const favicon = document.getElementById("favicon");
  if (favicon) {
    favicon.href = faviconToggle ? "index.html" : "index.html";
    faviconToggle = 1 - faviconToggle;
  }
}, 1000);
