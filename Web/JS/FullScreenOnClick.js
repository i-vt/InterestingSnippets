addEventListener("click", function() {
  const el = document.documentElement;
  const requestFullscreen = el.requestFullscreen || el.webkitRequestFullScreen || el.mozRequestFullScreen;
  if (requestFullscreen) {
    requestFullscreen.call(el);
  }
});
