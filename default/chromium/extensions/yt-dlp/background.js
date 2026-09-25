function sendUrl(url) {
  if (!url || !/^https?:/i.test(url)) return;

  // The native messaging host runs yt-dlp and owns all the desktop
  // notifications, so we just hand off the URL and ignore the reply.
  chrome.runtime.sendNativeMessage('com.omarchy.ytdlp', { url }, () => {
    void chrome.runtime.lastError;
  });
}

function triggerDownload(tab) {
  if (!tab) return;

  // The activeTab permission exposes tab.url whenever the user invokes the
  // extension — both via the toolbar click and the keyboard shortcut.
  if (tab.url) {
    sendUrl(tab.url);
    return;
  }

  // Fallback: read the URL straight from the page.
  if (tab.id === undefined) return;
  chrome.scripting
    .executeScript({ target: { tabId: tab.id }, func: () => location.href })
    .then((results) => sendUrl(results && results[0] && results[0].result))
    .catch(() => {});
}

function supportedVideoPage(url) {
  try {
    const host = new URL(url || '').hostname.toLowerCase();
    return host === 'youtu.be' || host === 'fb.watch'
      || ['youtube.com', 'facebook.com', 'tiktok.com', 'x.com', 'twitter.com']
        .some((domain) => host === domain || host.endsWith(`.${domain}`));
  } catch (_) {
    return false;
  }
}

function injectVideoWatcher(tab) {
  if (!tab || tab.id === undefined || !supportedVideoPage(tab.url)) return;
  chrome.scripting.executeScript({
    target: { tabId: tab.id, allFrames: true },
    files: ['content.js']
  }).catch(() => {});
}

function injectFocusedVideoTab() {
  chrome.tabs.query({ active: true, lastFocusedWindow: true }, (tabs) => {
    injectVideoWatcher(tabs && tabs[0]);
  });
}

// Restored tabs do not always reinject manifest content scripts. Explicitly
// attach to the active video tab on startup, navigation, and tab switches.
chrome.runtime.onStartup.addListener(injectFocusedVideoTab);
chrome.runtime.onInstalled.addListener(injectFocusedVideoTab);
chrome.tabs.onActivated.addListener(({ tabId }) => {
  chrome.tabs.get(tabId, injectVideoWatcher);
});
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.active)
    injectVideoWatcher(tab);
});

// Keyboard shortcut (Alt+Shift+D).
chrome.commands.onCommand.addListener((command) => {
  if (command === 'download-video') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      triggerDownload(tabs[0]);
    });
  }
});

// Clicking the extension's toolbar icon.
chrome.action.onClicked.addListener((tab) => {
  triggerDownload(tab);
});

// Forward active HTML5 video playback to the Omarchy media plugin. The plugin
// takes ownership only after MPV confirms it opened the page URL successfully.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== 'video-playing' || !message.payload) return;
  chrome.runtime.sendNativeMessage(
    'com.omarchy.ytdlp',
    { action: 'video-playing', payload: message.payload },
    (response) => {
      const error = chrome.runtime.lastError;
      sendResponse(error ? { handoff: false } : (response || { handoff: false }));
    }
  );
  return true;
});
