const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
let now = 1000, serial = 0;
const calls = [], canceled = [];
const signal = {connect() {}};
const context = {
    Date: {now: () => now}, Math,
    effect: {configChanged: signal, animationEnded: signal, readConfig: (_, fallback) => fallback},
    effects: {windowAdded: signal, stackingOrder: []},
    animationTime: n => n, QEasingCurve: {OutCubic: 1},
    Effect: {Translation: 1, Scale: 2, WindowForceBlurRole: 3},
    animate(options) { calls.push(options); return options.animations.map(() => ++serial); },
    cancel(ids) { canceled.push(Array.from(ids)); },
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
const w = window();
now += 20;
let animations = move(w, {x: 400});
assert.equal(animations[0].from.value1, -400);
assert.equal(animations.length, 1);
assert.equal(w.blur, null);
now += 25;
animations = move(w, {x: 800});
assert.ok(Math.abs(animations[0].from.value1 - (-400 - 400 * 0.729)) < 1e-9);
assert.deepEqual(canceled[0], [1]);
assert.equal(w.geometryChangeData.animationInstances, 1);
now += 250;
animations = move(w, {x: 900});
assert.equal(animations[0].from.value1, -100);
const resized = window();
now += 20;
move(resized, {width: 200});
now += 25;
animations = move(resized, {width: 400});
assert.equal(animations.length, 2);
assert.equal(resized.blur, true);
assert.ok(Math.abs(animations[1].from.value1 - (1 - 0.5 * 0.729) * 0.5) < 1e-9);
assert.ok(Math.abs(animations[0].from.value1 - (-100 - 50 * 0.729)) < 1e-9);
motionEffect.restoreForceBlurState(resized);
motionEffect.restoreForceBlurState(resized);
assert.equal(resized.geometryChangeData.animationInstances, 0);
assert.equal(resized.geometryChangeData.motion, null);
assert.equal(resized.blur, null);
const before = calls.length;
move(resized, {});
assert.equal(calls.length, before);
motionEffect.restoreForceBlurState(resized);
assert.equal(resized.geometryChangeData.animationInstances, 0);
console.log('Geometry motion continuity, resize continuity, cancellation and cleanup passed.');
