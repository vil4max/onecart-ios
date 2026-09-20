# App-owned. Runtime recipes come from Tooling/.
import 'Tooling/justfile'

demo role="owner":
    #!/usr/bin/env bash
    set -euo pipefail
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}}
    MAIN_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c "import json, sys; data=json.load(sys.stdin); print(next((d['udid'] for devs in data.get('devices', {}).values() for d in devs if d.get('name') == 'iPhone 17' and d.get('state') == 'Booted'), ''))" 2>/dev/null || true)"
    if [[ -n "$MAIN_ID" ]]; then
        APP_PATH="$(xcrun simctl get_app_container "$MAIN_ID" com.vil555tim.onecart app 2>/dev/null || true)"
        if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
            for udid in $(xcrun simctl list devices | grep "Booted" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'); do
                if [[ "$udid" != "$MAIN_ID" ]]; then
                    echo "Syncing build to booted simulator $udid..."
                    xcrun simctl install "$udid" "$APP_PATH" 2>/dev/null || true
                    xcrun simctl launch "$udid" com.vil555tim.onecart -oneCartDemoUI -oneCartDemoRole {{role}} 2>/dev/null || true
                fi
            done
        fi
    fi

demo-tab role="owner" tab="cart":
    #!/usr/bin/env bash
    set -euo pipefail
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}} -oneCartDemoTab {{tab}}
    MAIN_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c "import json, sys; data=json.load(sys.stdin); print(next((d['udid'] for devs in data.get('devices', {}).values() for d in devs if d.get('name') == 'iPhone 17' and d.get('state') == 'Booted'), ''))" 2>/dev/null || true)"
    if [[ -n "$MAIN_ID" ]]; then
        APP_PATH="$(xcrun simctl get_app_container "$MAIN_ID" com.vil555tim.onecart app 2>/dev/null || true)"
        if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
            for udid in $(xcrun simctl list devices | grep "Booted" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'); do
                if [[ "$udid" != "$MAIN_ID" ]]; then
                    echo "Syncing build to booted simulator $udid..."
                    xcrun simctl install "$udid" "$APP_PATH" 2>/dev/null || true
                    xcrun simctl launch "$udid" com.vil555tim.onecart -oneCartDemoUI -oneCartDemoRole {{role}} -oneCartDemoTab {{tab}} 2>/dev/null || true
                fi
            done
        fi
    fi
