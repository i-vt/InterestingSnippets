let intervalId;

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
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
    browser.browserAction.setBadgeText({ text: '' });
    browser.browserAction.setIcon({ path: "icon_inactive.png" });
    console.log("Auto-refresh stopped");
  } else {
    intervalId = setInterval(refreshPage, 5 * 60 * 1000); // 5 minutes in milliseconds
    browser.browserAction.setBadgeText({ text: 'ON' });
    browser.browserAction.setIcon({ path: "icon_active.png" });
    console.log("Auto-refresh started");
  }
}

browser.browserAction.onClicked.addListener(startAutoRefresh);