import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
function fixture(origin = 'https://music.youtube.com') {
 const sent = [], listeners = new Map(), clicked = [];
 const media = { duration: 120, playbackRate: 1, currentTime: 5, paused: true, ended: false, seekable: { length: 1 }, play: async () => { media.paused = false; }, pause: () => {media.paused = true;}, addEventListener: (e,f) => listeners.set(e,f), removeEventListener: e => listeners.delete(e) };
 let active = media; let ad = false;
 const control = name => ({ hasAttribute: () => false, getAttribute: () => null, click: () => clicked.push(name) });
 const document = { querySelector(selector) { if(selector === 'video, audio') return active; if(selector === '.ad-showing') return ad ? {} : null; if(selector.includes('.title')) return { textContent: ' Track ' }; if(selector.includes('browse/')) return { textContent: 'Album' }; if(selector.includes('.byline')) return { textContent: 'Artist' }; if(selector.endsWith('img')) return null; return control(selector); } };
 const window = { webkit: { messageHandlers: { player: { postMessage: s => sent.push(s) } } }, setTimeout: fn => { fn(); return 1; }, addEventListener() {} }; window.top = window;
 vm.runInNewContext(readFileSync('dist/player-adapter.js','utf8'), { window, document, location: { origin }, performance: { now: () => 2000 }, MutationObserver: class { observe() {} } });
 return { window, media, sent, clicked, setAd: value => {ad = value;}, removeMedia: () => {active=null;}, listeners };
}
test('publishes typed metadata and commands control actual media fixture', async () => {
 const f = fixture(); assert.equal(f.sent[0].title, 'Track'); assert.equal(f.sent[0].isPlaying,false);
 await f.window.ytmCommand({type:'toggle'}); assert.equal(f.media.paused,false); assert.equal(f.sent.at(-1).isPlaying,true);
 await f.window.ytmCommand({type:'pause'}); assert.equal(f.media.paused,true);
 await f.window.ytmCommand({type:'seek',time:999}); assert.equal(f.media.currentTime,120);
 await f.window.ytmCommand({type:'next'}); assert.equal(f.clicked.length,1);
});
test('does not install bridge outside music origin', () => {const f=fixture('https://accounts.google.com'); assert.equal(f.sent.length,0); assert.equal(f.window.ytmCommand,undefined);});
test('missing media resets progress without throwing', async () => {const f=fixture();f.removeMedia();await f.window.ytmCommand({type:'toggle'});assert.equal(f.sent.at(-1).currentTime,null);assert.equal(f.sent.at(-1).canSeek,false);});

test('reports advertisements separately from song playback', async () => {
 const f = fixture(); assert.equal(f.sent[0].isAd,false);
 f.setAd(true); await f.window.ytmCommand({type:'pause'}); assert.equal(f.sent.at(-1).isAd,true);
 f.setAd(false); await f.window.ytmCommand({type:'pause'}); assert.equal(f.sent.at(-1).isAd,false);
});

test('captures album and playback rate for rich-lyrics matching', () => {
 const f=fixture(); assert.equal(f.sent[0].album,'Album'); assert.equal(f.sent[0].playbackRate,1);
});
