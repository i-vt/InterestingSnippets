function refreshPage() {
  browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
    if (tabs[0]) {
      browser.tabs.reload(tabs[0].id);
    }
  }).catch((error) => {
    console.error(`Error reloading tab: ${error}`);
  });
}

let intervalId;

function startAutoRefresh() {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
    console.log("Auto-refresh stopped");
  } else {
    intervalId = setInterval(refreshPage, 5 * 60 * 1000); // 5 minutes in milliseconds
    console.log("Auto-refresh started");
  }
}

browser.action.onClicked.addListener(startAutoRefresh);