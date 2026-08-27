import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

export default class AmbedFly extends Extension {
    enable() {
        this.frames = [
            this.dir.get_child('assets').get_child('fly_frame1.png').get_path(),
            this.dir.get_child('assets').get_child('fly_frame2.png').get_path(),
            this.dir.get_child('assets').get_child('fly_frame3.png').get_path()
        ];

        this.currentFrame = 0;

        this.SIZE = 45;
        this.FLY_SIZE = 35;

        this.flyContainer = new St.Bin({
            reactive: false
        });

        this.flyContainer.set_size(this.SIZE, this.SIZE);
        this.flyContainer.set_pivot_point(0.5, 0.5);

        this.fly = new St.Icon({
            gicon: Gio.FileIcon.new(
                Gio.File.new_for_path(this.frames[0])
            ),
            icon_size: this.FLY_SIZE,
            reactive: false
        });

        this.fly.set_pivot_point(0.5, 0.5);
        this.flyContainer.set_child(this.fly);

        Main.layoutManager.addChrome(this.flyContainer);

        this.monitor = Main.layoutManager.primaryMonitor;

        this.posX =
            this.monitor.x +
            Math.random() * Math.max(1, this.monitor.width - this.SIZE);

        this.posY =
            this.monitor.y +
            Math.random() * Math.max(1, this.monitor.height - this.SIZE);

        this.angle = Math.random() * 360;
        this.speed = 1.5;
        this.targetSpeed = 2;

        this.angularVelocity = 0;
        this.wanderForce = 0;

        this.mode = 'wander';
        this.modeUntil = 0;

        this.pointerX = 0;
        this.pointerY = 0;
        this.lastPointerX = 0;
        this.lastPointerY = 0;

        this.pointerVelocityX = 0;
        this.pointerVelocityY = 0;

        this.lastWindowRect = null;
        this.windowTargetX = 0;
        this.windowTargetY = 0;

        this.flyContainer.set_position(
            this.posX,
            this.posY
        );

        this.frameTimer = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            33,
            () => {
                if (!this.fly)
                    return GLib.SOURCE_REMOVE;

                this.currentFrame =
                    (this.currentFrame + 1) % this.frames.length;

                this.fly.set_gicon(
                    Gio.FileIcon.new(
                        Gio.File.new_for_path(
                            this.frames[this.currentFrame]
                        )
                    )
                );

                return GLib.SOURCE_CONTINUE;
            }
        );

        this.moveTimer = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            16,
            () => {
                if (!this.flyContainer)
                    return GLib.SOURCE_REMOVE;

                this._updatePointer();
                this._updateBehavior();
                this._move();

                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    _angleDiff(target, current) {
        let diff = (target - current) % 360;

        if (diff > 180)
            diff -= 360;

        if (diff < -180)
            diff += 360;

        return diff;
    }

    _updatePointer() {
        const [x, y] = global.get_pointer();

        this.pointerVelocityX =
            (x - this.lastPointerX) * 0.35 +
            this.pointerVelocityX * 0.65;

        this.pointerVelocityY =
            (y - this.lastPointerY) * 0.35 +
            this.pointerVelocityY * 0.65;

        this.pointerX = x;
        this.pointerY = y;

        this.lastPointerX = x;
        this.lastPointerY = y;
    }

    _updateBehavior() {
        const now = GLib.get_monotonic_time() / 1000;
        const window = global.display.focus_window;

        if (
            window &&
            !window.minimized &&
            typeof window.get_frame_rect === 'function'
        ) {
            const rect = window.get_frame_rect();

            if (this.lastWindowRect) {
                const moved =
                    Math.abs(rect.x - this.lastWindowRect.x) > 1 ||
                    Math.abs(rect.y - this.lastWindowRect.y) > 1;

                if (moved) {
                    this.mode = 'window';
                    this.modeUntil = now + 650;

                    this.windowTargetX =
                        rect.x +
                        rect.width * (0.2 + Math.random() * 0.6);

                    this.windowTargetY = rect.y - 15;
                }
            }

            this.lastWindowRect = {
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            };
        } else {
            this.lastWindowRect = null;
        }

        if (now > this.modeUntil) {
            if (this.mode !== 'wander') {
                this.mode = 'wander';
                this.modeUntil =
                    now + 1800 + Math.random() * 3000;
            } else if (Math.random() < 0.0035) {
                this.mode = 'cursor';
                this.modeUntil =
                    now + 1800 + Math.random() * 2600;
            }
        }
    }

    _move() {
        if (!this.flyContainer)
            return;

        this.monitor = Main.layoutManager.primaryMonitor;

        const minX = this.monitor.x;
        const minY = this.monitor.y;

        const maxX =
            this.monitor.x +
            this.monitor.width -
            this.SIZE;

        const maxY =
            this.monitor.y +
            this.monitor.height -
            this.SIZE;

        let steer = 0;
        let speedBoost = 0;

        if (this.mode === 'cursor') {
            const targetX =
                this.pointerX +
                this.pointerVelocityX * 7;

            const targetY =
                this.pointerY +
                this.pointerVelocityY * 7;

            const dx = targetX - this.posX;
            const dy = targetY - this.posY;

            const distance = Math.hypot(dx, dy);

            let targetAngle =
                Math.atan2(dy, dx) * 180 / Math.PI;

            if (distance < 90) {
                targetAngle +=
                    Math.sin(this.angle * Math.PI / 180) * 35;
            }

            steer =
                this._angleDiff(
                    targetAngle,
                    this.angle
                ) * 0.055;

            speedBoost =
                Math.min(1.4, distance / 140);

        } else if (this.mode === 'window') {
            const targetAngle =
                Math.atan2(
                    this.windowTargetY - this.posY,
                    this.windowTargetX - this.posX
                ) * 180 / Math.PI;

            steer =
                this._angleDiff(
                    targetAngle,
                    this.angle
                ) * 0.06;

            speedBoost = 1.2;

        } else {
            this.wanderForce +=
                (Math.random() - 0.5) * 0.55;

            this.wanderForce *= 0.96;

            this.wanderForce =
                Math.max(
                    -2.2,
                    Math.min(2.2, this.wanderForce)
                );

            steer = this.wanderForce;
        }

        this.angularVelocity +=
            steer +
            (Math.random() - 0.5) * 0.55;

        this.angularVelocity *= 0.91;

        this.angularVelocity =
            Math.max(
                -6,
                Math.min(6, this.angularVelocity)
            );

        this.angle += this.angularVelocity;

        if (Math.random() < 0.008) {
            this.targetSpeed =
                0.7 + Math.random() * 3.2;
        }

        this.speed +=
            (this.targetSpeed - this.speed) * 0.035;

        const turnFactor =
            1 -
            Math.min(
                0.3,
                Math.abs(this.angularVelocity) / 22
            );

        const currentSpeed =
            (this.speed + speedBoost) * turnFactor;

        this.posX +=
            Math.cos(this.angle * Math.PI / 180) *
            currentSpeed;

        this.posY +=
            Math.sin(this.angle * Math.PI / 180) *
            currentSpeed;

        if (this.posX < minX) {
            this.posX = minX;
            this.angle = 180 - this.angle;
            this.angularVelocity *= 0.55;
        } else if (this.posX > maxX) {
            this.posX = maxX;
            this.angle = 180 - this.angle;
            this.angularVelocity *= 0.55;
        }

        if (this.posY < minY) {
            this.posY = minY;
            this.angle = -this.angle;
            this.angularVelocity *= 0.55;
        } else if (this.posY > maxY) {
            this.posY = maxY;
            this.angle = -this.angle;
            this.angularVelocity *= 0.55;
        }

        this.flyContainer.set_position(
            this.posX,
            this.posY
        );

        this.fly.rotation_angle_z =
            this.angle + 90;
    }

    disable() {
        if (this.frameTimer) {
            GLib.Source.remove(this.frameTimer);
            this.frameTimer = null;
        }

        if (this.moveTimer) {
            GLib.Source.remove(this.moveTimer);
            this.moveTimer = null;
        }

        if (this.flyContainer) {
            this.flyContainer.destroy();
            this.flyContainer = null;
        }

        this.fly = null;
        this.frames = null;
        this.lastWindowRect = null;
    }
}
