// SPDX-FileCopyrightText: Peter Fajdiga
// SPDX-License-Identifier: GPL-3.0-only
// Adapted from the installed Geometry Change 1.5 effect.
"use strict";

class GeometryChangeEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.restoreForceBlurState.bind(this));

        const manageFn = this.manage.bind(this);
        effects.windowAdded.connect(manageFn);
        effects.stackingOrder.forEach(manageFn);

        this.loadConfig();
    }

    loadConfig() {
        const duration = effect.readConfig("Duration", 250);
        this.duration = animationTime(duration);
        this.excludedWindowClasses = effect.readConfig("ExcludedWindowClasses", "krunner,yakuake").split(",");
    }

    manage(window) {
        window.geometryChangeData = {
            createdTime: Date.now(),
            animationInstances: 0,
            maximizedStateAboutToChange: false,
            motion: null,
        };
        window.windowFrameGeometryChanged.connect(
            this.onWindowFrameGeometryChanged.bind(this),
        );
        window.windowMaximizedStateAboutToChange.connect(
            this.onWindowMaximizedStateAboutToChange.bind(this),
        );
        window.windowStartUserMovedResized.connect(
            this.onWindowStartUserMovedResized.bind(this),
        );
        window.windowFinishUserMovedResized.connect(
            this.onWindowFinishUserMovedResized.bind(this),
        );
    }

    restoreForceBlurState(window) {
        window.geometryChangeData.animationInstances = Math.max(0,
            window.geometryChangeData.animationInstances - 1);
        if (window.geometryChangeData.animationInstances === 0) {
            window.setData(Effect.WindowForceBlurRole, null);
            window.geometryChangeData.motion = null;
        }
    }

    isWindowClassExluded(windowClass) {
        return windowClass.split(" ").some(part => this.excludedWindowClasses.includes(part));
    }

    onWindowFrameGeometryChanged(window, oldGeometry) {
        const windowTypeSupportsAnimation = window.normalWindow || window.dialog || window.modal;
        const isUserMoveResize = window.move || window.resize || this.userResizing;
        const maximizationChange = window.geometryChangeData.maximizedStateAboutToChange;
        window.geometryChangeData.maximizedStateAboutToChange = false;
        if (
            !window.managed ||
            !window.visible ||
            !window.onCurrentDesktop ||
            window.minimized ||
            !windowTypeSupportsAnimation ||
            isUserMoveResize && !maximizationChange ||
            this.isWindowClassExluded(window.windowClass)
        ) {
            return;
        }

        const windowAgeMs = Date.now() - window.geometryChangeData.createdTime;
        if (windowAgeMs < 0) {
            // May happen after time zone change. Let's fix the created time, so it's not in the future.
            window.geometryChangeData.createdTime = Date.now();
        } else if(windowAgeMs < 10) {
            // Some windows are moved or resized immediately after being created. We don't want to animate that.
            return;
        }

        const newGeometry = window.geometry;
        const xDelta = newGeometry.x - oldGeometry.x;
        const yDelta = newGeometry.y - oldGeometry.y;
        const widthDelta = newGeometry.width - oldGeometry.width;
        const heightDelta = newGeometry.height - oldGeometry.height;
        if (!xDelta && !yDelta && !widthDelta && !heightDelta) return;
        if (newGeometry.width <= 0 || newGeometry.height <= 0) return;
        const widthRatio = oldGeometry.width / newGeometry.width;
        const heightRatio = oldGeometry.height / newGeometry.height;

        // Continue from the currently painted transform. Otherwise repeated
        // Karousel focus changes stack animations and produce visible jerks.
        const previous = window.geometryChangeData.motion;
        var offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1;
        if (previous) {
            const progress = Math.max(0, Math.min(1,
                (Date.now() - previous.started) / Math.max(1, previous.duration)));
            // Match OutCubic exactly: gentler initial speed than OutExpo,
            // with zero velocity as the window settles.
            const remaining = Math.pow(1 - progress, 3);
            offsetX = previous.x * remaining;
            offsetY = previous.y * remaining;
            scaleX = 1 + (previous.scaleX - 1) * remaining;
            scaleY = 1 + (previous.scaleY - 1) * remaining;
            cancel(previous.ids);
            // Cancellation does not emit animationEnded in KWin.
            window.geometryChangeData.animationInstances = 0;
        }
        const motion = {
            x: offsetX - xDelta - widthDelta / 2,
            y: offsetY - yDelta - heightDelta / 2,
            scaleX: scaleX * widthRatio,
            scaleY: scaleY * heightRatio,
            started: Date.now(), duration: this.duration,
        };
        const animations = [
            {
                type: Effect.Translation,
                from: {
                    value1: motion.x,
                    value2: motion.y,
                },
                to: {
                    value1: 0,
                    value2: 0,
                },
            },
        ];
        const resizing = Math.abs(motion.scaleX - 1) > 0.00001 ||
            Math.abs(motion.scaleY - 1) > 0.00001;
        if (resizing) animations.push({
                type: Effect.Scale,
                from: {
                    value1: motion.scaleX,
                    value2: motion.scaleY,
                },
                to: {
                    value1: 1,
                    value2: 1,
                },
            });

        window.geometryChangeData.animationInstances += animations.length;
        // Ordinary Karousel scrolling needs only translation. Avoid a scale
        // pass and forced background blur for every moving window.
        window.setData(Effect.WindowForceBlurRole, resizing ? true : null);

        motion.ids = animate({
            window: window,
            duration: this.duration,
            curve: QEasingCurve.OutCubic,
            animations: animations,
        });
        window.geometryChangeData.motion = motion;
    }

    onWindowMaximizedStateAboutToChange(window, horizontal, vertical) {
        window.geometryChangeData.maximizedStateAboutToChange = true;
    }

    onWindowStartUserMovedResized(window) {
        this.userResizing = true;
    }

    onWindowFinishUserMovedResized(window) {
        this.userResizing = false;
    }
}

new GeometryChangeEffect();
