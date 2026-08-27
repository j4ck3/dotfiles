const clearHistory = () =>
  chrome.history.deleteAll().catch((error) => {
    console.error("Failed to clear web-app history:", error);
  });

chrome.history.onVisited.addListener((item) => {
  if (!item.url) return;

  chrome.history.deleteUrl({ url: item.url }).catch((error) => {
    console.error(`Failed to remove ${item.url} from history:`, error);
  });
});

chrome.runtime.onInstalled.addListener(clearHistory);
chrome.runtime.onStartup.addListener(clearHistory);

// Also clear when the service worker wakes after being suspended.
void clearHistory();
