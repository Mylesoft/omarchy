(() => {
  const handoffState = new WeakMap();

  function tryHandoff(video) {
    if (!(video instanceof HTMLVideoElement)) return;
    const url = location.href;
    if (!/^https:\/\//i.test(url) || video.readyState < 2) return;
    const state = handoffState.get(video) || {};
    if (state.url === url && (state.accepted || state.inFlight
        || Date.now() - (state.lastAttempt || 0) < 2000)) return;
    handoffState.set(video, { url, inFlight: true, lastAttempt: Date.now() });

    const metaTitle = document.querySelector('meta[property="og:title"]')?.content;
    const payload = {
      url,
      title: String(metaTitle || document.title || 'Video').slice(0, 240),
      poster: String(video.poster || '').slice(0, 1500),
      startSeconds: Number.isFinite(video.currentTime) ? video.currentTime : 0,
      playing: true
    };
    chrome.runtime.sendMessage({ type: 'video-playing', payload }, (response) => {
      const accepted = !chrome.runtime.lastError && response?.handoff === true;
      if (accepted) {
        handoffState.set(video, { url, accepted: true });
        if (!video.paused) video.pause();
      } else {
        handoffState.set(video, { url, lastAttempt: Date.now() });
        // Retry while playback remains active: the shell may still be starting
        // after the browser has already begun autoplaying the restored tab.
        if (!video.paused) setTimeout(() => tryHandoff(video), 2200);
      }
    });
  }

  function attach(video) {
    if (video.dataset.omarchyMediaListener === 'v2') return;
    if (video.dataset.omarchyMediaListener !== 'v2') {
      video.dataset.omarchyMediaListener = 'v2';
      video.addEventListener('playing', () => tryHandoff(video));
    }
    if (!video.paused) tryHandoff(video);
  }

  document.querySelectorAll('video').forEach(attach);
  new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node instanceof HTMLVideoElement) attach(node);
        else if (node.querySelectorAll) node.querySelectorAll('video').forEach(attach);
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
