function refreshPage() {
  browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
    if (tabs[0]) {
      browser.tabs.reload(tabs[0].id);
    }
  }).catch((error) => {
    console.error(`Error reloading tab: ${error}`);
  });
}

function startAutoRefresh() {
  console.log("Auto-refresh started");
  setInterval(refreshPage, 5 * 60 * 1000); // 5 minutes in milliseconds
}

browser.browserAction.onClicked.addListener(startAutoRefresh);