import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const REFRESH_INTERVAL_SECONDS = 30;
const HEADSET_CACHE_MAX_AGE_SECONDS = 300;
const POWER_SUPPLY_PATH = '/sys/class/power_supply';
const MOUSE_CHARGING_ICON = 'battery-full-charging-symbolic';

function readText(path) {
    try {
        const [success, contents] = Gio.File.new_for_path(path).load_contents(null);
        if (!success)
            return null;

        return new TextDecoder().decode(contents).trim();
    } catch (_error) {
        return null;
    }
}

function parsePercentage(value) {
    if (value === null || !/^\d+$/.test(value))
        return null;

    const percentage = Number.parseInt(value, 10);
    return percentage >= 0 && percentage <= 100 ? percentage : null;
}

function readMouseBattery() {
    let enumerator = null;

    try {
        enumerator = Gio.File.new_for_path(POWER_SUPPLY_PATH).enumerate_children(
            'standard::name',
            Gio.FileQueryInfoFlags.NONE,
            null
        );

        let fallback = null;
        for (let info = enumerator.next_file(null); info; info = enumerator.next_file(null)) {
            const entry = info.get_name();
            if (!entry.startsWith('hidpp_battery_'))
                continue;

            const basePath = `${POWER_SUPPLY_PATH}/${entry}`;
            const percentage = parsePercentage(readText(`${basePath}/capacity`));
            if (percentage === null)
                continue;

            const battery = {
                percentage,
                charging: readText(`${basePath}/status`) === 'Charging',
            };
            const model = readText(`${basePath}/model_name`) ?? '';
            if (model.includes('G502'))
                return battery;

            fallback ??= battery;
        }

        return fallback;
    } catch (_error) {
        return null;
    } finally {
        if (enumerator !== null)
            enumerator.close(null);
    }
}

function readHeadsetPercentage() {
    const cachePath = `${GLib.get_user_runtime_dir()}/logitech-headset-battery/percent`;
    const cacheFile = Gio.File.new_for_path(cachePath);

    try {
        const info = cacheFile.query_info(
            'time::modified',
            Gio.FileQueryInfoFlags.NONE,
            null
        );
        const modifiedAt = info.get_attribute_uint64('time::modified');
        const now = Math.floor(GLib.get_real_time() / GLib.USEC_PER_SEC);

        if (modifiedAt <= 0 || now - modifiedAt > HEADSET_CACHE_MAX_AGE_SECONDS)
            return null;
    } catch (_error) {
        return null;
    }

    return parsePercentage(readText(cachePath));
}

class DeviceBattery extends St.BoxLayout {
    static {
        GObject.registerClass(this);
    }

    constructor(iconName, accessibleName) {
        super({
            style: 'spacing: 3px;',
            y_align: Clutter.ActorAlign.CENTER,
        });

        this.accessible_name = accessibleName;
        this._defaultIconName = iconName;
        this._label = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._icon = new St.Icon({
            icon_name: iconName,
            style_class: 'system-status-icon',
        });
        this.add_child(this._icon);
        this.add_child(this._label);
    }

    setPercentage(percentage, charging = false) {
        this.visible = percentage !== null;
        if (percentage !== null) {
            this._icon.icon_name = charging ? MOUSE_CHARGING_ICON : this._defaultIconName;
            this._label.text = `${percentage}%`;
        }
    }
}

class LogitechBatteryIndicator extends PanelMenu.Button {
    static {
        GObject.registerClass(this);
    }

    constructor() {
        super(0.0, 'Logitech device batteries', true);

        const box = new St.BoxLayout({style: 'spacing: 8px;'});
        this._mouse = new DeviceBattery('input-mouse-symbolic', 'Logitech G502 battery');
        this._headset = new DeviceBattery('audio-headphones-symbolic', 'Logitech G Pro X battery');
        box.add_child(this._mouse);
        box.add_child(this._headset);
        this.add_child(box);

        this.refresh();
    }

    refresh() {
        const mouseBattery = readMouseBattery();
        const headsetPercentage = readHeadsetPercentage();

        this._mouse.setPercentage(mouseBattery?.percentage ?? null, mouseBattery?.charging ?? false);
        this._headset.setPercentage(headsetPercentage);
        this.visible = mouseBattery !== null || headsetPercentage !== null;
    }
}

export default class LogitechBatteryExtension extends Extension {
    enable() {
        this._indicator = new LogitechBatteryIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);

        this._refreshSource = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            REFRESH_INTERVAL_SECONDS,
            () => {
                this._indicator.refresh();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    disable() {
        if (this._refreshSource) {
            GLib.Source.remove(this._refreshSource);
            this._refreshSource = null;
        }

        this._indicator?.destroy();
        this._indicator = null;
    }
}
