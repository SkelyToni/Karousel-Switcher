const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
let now = 1000, serial = 0;
const calls = [];
const signal = {connect() {}};
const context = {
    Date: {now: () => now}, Math,
    effect: {configChanged: signal, animationEnded: signal, readConfig: (_, fallback) => fallback},
    effects: {windowAdded: signal, stackingOrder: []},
    animationTime: n => n, QEasingCurve: {OutCubic: 1, InOutCubic: 2},
    Effect: {Translation: 1, Scale: 2, WindowForceBlurRole: 3},
    animate(options) { calls.push(options); return options.animations.map(() => ++serial); },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../geometry-change/main.js'), 'utf8') +
    '\nglobalThis.motionEffect = new GeometryChangeEffect();', context);
const motionEffect = context.motionEffect;
function window() {
    const w = {managed: true, visible: true, onCurrentDesktop: true, normalWindow: true,
        windowClass: 'test test', geometry: {x: 0, y: 0, width: 100, height: 100},
        windowFrameGeometryChanged: signal, windowMaximizedStateAboutToChange: signal,
        windowStartUserMovedResized: signal, windowFinishUserMovedResized: signal,
        blur: null, setData(role, value) { this.blur = value; }};
    motionEffect.manage(w);
    return w;
}
function move(w, next) {
    const old = w.geometry;
    w.geometry = {...old, ...next};
    motionEffect.onWindowFrameGeometryChanged(w, old);
    return calls.at(-1).animations;
}
function ended(w, count) { while (count--) motionEffect.restoreForceBlurState(w); }
const w = window();
now += 20;
let animations = move(w, {x: 400});
assert.equal(animations[0].from.value1, -400);
assert.equal(animations.length, 1);
assert.equal(calls.at(-1).curve, 1); // from rest: OutCubic
assert.equal(w.blur, null);
now += 25;
animations = move(w, {x: 800});
// Layered on the running step, not cancelled: only the new delta is added,
// easing in from zero velocity so the window's speed stays continuous.
assert.equal(animations[0].from.value1, -400);
assert.equal(calls.at(-1).curve, 2);
assert.equal(w.geometryChangeData.animationInstances, 2);
ended(w, 2);
now += 250;
animations = move(w, {x: 900});
assert.equal(animations[0].from.value1, -100);
assert.equal(calls.at(-1).curve, 1);
ended(w, 1);
const resized = window();
now += 20;
move(resized, {width: 200});
assert.equal(resized.blur, true);
now += 25;
animations = move(resized, {x: 10});
assert.equal(animations.length, 1);
assert.equal(resized.blur, true); // a running resize keeps its blur
animations = move(resized, {width: 400});
assert.equal(animations.length, 2);
assert.equal(animations[0].from.value1, -100);
assert.equal(animations[1].from.value1, 0.5);
ended(resized, 4);
assert.equal(resized.blur, true);
ended(resized, 1);
assert.equal(resized.geometryChangeData.animationInstances, 0);
assert.equal(resized.blur, null);
const before = calls.length;
move(resized, {});
assert.equal(calls.length, before);
motionEffect.restoreForceBlurState(resized);
assert.equal(resized.geometryChangeData.animationInstances, 0);
console.log('Geometry motion layering, easing choice, blur lifetime and cleanup passed.');
