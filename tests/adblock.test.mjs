import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync('src-tauri/native/touchbar/AdBlocker.swift', 'utf8')
  .split('enum AdPlaybackScript {')[1].split('static let source = #"""')[1].split('"""#')[0];
function fixture({ ad = false, duration = 30, paused = false, skip = false, origin = 'https://music.youtube.com' } = {}) {
  const media = { currentTime: 2, duration, paused };
  let tick, clicks = 0;
  const player = { classList: { contains: () => ad }, querySelector: s => s === 'video, audio' ? media : skip ? { disabled: false, getAttribute: () => null, click: () => { clicks++; ad = false; } } : null };
  const window = { setInterval: fn => { tick = fn; } }; window.top = window;
  vm.runInNewContext(source, { window, location: { origin }, document: { querySelector: () => player, addEventListener() {} } });
  return { media, tick: () => tick?.(), clicks: () => clicks };
}
test('advances an active ad while leaving normal songs untouched', () => {
  const ad = fixture({ ad: true }); ad.tick(); assert.equal(ad.media.currentTime, 30);
  const song = fixture(); song.tick(); assert.equal(song.media.currentTime, 2);
});
test('clicking skip never seeks the song that replaces the ad', () => {
  const f = fixture({ ad: true, skip: true }); f.tick(); f.tick();
  assert.equal(f.clicks(), 1); assert.equal(f.media.currentTime, 2);
});
test('leaves paused, unknown-duration, live, and other-origin media alone', () => {
  for (const options of [{ paused: true }, { duration: NaN }, { duration: Infinity }, { duration: 0 }, { origin: 'https://accounts.google.com' }]) {
    const f = fixture({ ad: true, ...options }); f.tick(); assert.equal(f.media.currentTime, 2);
  }
});
