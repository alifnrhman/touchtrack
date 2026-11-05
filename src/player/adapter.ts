import type { PlayerState, PlayerCommand } from '../types/player';
declare global { interface Window { webkit: { messageHandlers: { player: { postMessage(value: PlayerState): void } } }; ytmCommand?: (command: PlayerCommand) => Promise<void>; } }
if (location.origin === 'https://music.youtube.com' && window.top === window) {
  let media: HTMLMediaElement | null = null, previous = '', timer = 0, lastSent = 0;
  const button = (name: string) => document.querySelector<HTMLButtonElement>(`ytmusic-player-bar .${name}-button`);
  const enabled = (element: HTMLElement | null) => !!element && !element.hasAttribute('disabled') && element.getAttribute('aria-disabled') !== 'true';
  const text = (selector: string) => document.querySelector(selector)?.textContent?.trim().slice(0, 1024) || null;
  const finite = (value: number | undefined) => value !== undefined && Number.isFinite(value) && value >= 0 ? value : null;
  const changed = () => { if (!timer) timer = window.setTimeout(() => { timer = 0; update(); }, 200); };
  const progress = () => { if (performance.now() - lastSent >= 1000) update(); };
  const events = ['play','pause','loadedmetadata','durationchange','emptied','ended','seeking','seeked','waiting','playing'];
  function update() {
    const next = document.querySelector<HTMLMediaElement>('video, audio');
    if (media !== next) {
      if (media) { events.forEach(e => media!.removeEventListener(e, update)); media.removeEventListener('timeupdate', progress); }
      media = next;
      if (media) { events.forEach(e => media!.addEventListener(e, update)); media.addEventListener('timeupdate', progress); }
    }
    const duration = finite(media?.duration);
    const artwork = document.querySelector<HTMLImageElement>('ytmusic-player-bar img')?.src;
    const state: PlayerState = {
      title: text('ytmusic-player-bar .title'),
      artist: text('ytmusic-player-bar .byline a') || text('ytmusic-player-bar .byline'),
      album: text('ytmusic-player-bar .byline a[href*="browse/"]'),
      playbackRate: finite(media?.playbackRate) || 1,
      artworkUrl: artwork && artwork.length <= 4096 ? artwork : null,
      duration, currentTime: finite(media?.currentTime),
      isAd: !!document.querySelector('.ad-showing'),
      isPlaying: !!media && !media.paused && !media.ended,
      canSeek: !!media && !!duration && media.seekable.length > 0,
      canNext: enabled(button('next')), canPrevious: enabled(button('previous')),
    };
    const value = JSON.stringify(state);
    if (value !== previous) { previous = value; lastSent = performance.now(); window.webkit.messageHandlers.player.postMessage(state); }
  }
  window.ytmCommand = async command => {
    if (location.origin !== 'https://music.youtube.com') return;
    const video = document.querySelector<HTMLMediaElement>('video, audio');
    switch (command.type) {
      case 'play': if(video) await video.play(); break;
      case 'pause': video?.pause(); break;
      case 'toggle': if(video) { if(video.paused) await video.play(); else video.pause(); } break;
      case 'next': case 'previous': { const el = button(command.type); if(enabled(el)) el!.click(); break; }
      case 'seek': if(video && Number.isFinite(command.time) && Number.isFinite(video.duration) && video.seekable.length) video.currentTime = Math.max(0, Math.min(command.time, video.duration)); break;
    }
    update();
  };
  new MutationObserver(changed).observe(document, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['disabled','aria-disabled','src'] });
  window.addEventListener('pageshow', changed); window.addEventListener('popstate', changed); update();
}
