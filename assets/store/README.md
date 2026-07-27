# Store / TestFlight visuals

Captured from iPhone 17 simulator (1206×2622).

| File | Use | State |
|------|-----|-------|
| `screenshots/01-welcome.png` | Welcome + three-step trolley metaphor + Sign in with Apple | current |
| `preview/tf-welcome-siwa.mp4` | Short preview: Welcome → SIWA → system prompt | stale — recorded before the three-step Welcome |

Apple 6.7" slot expects **1290×2796**. Current sim size is **1206×2622** — upsample or re-capture before App Store submission.

Past Welcome needs Apple ID on simulator or device for more screens.

## Re-capture

```bash
xcrun simctl status_bar <udid> override --time "09:41" --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charging --batteryLevel 100
xcrun simctl io <udid> screenshot --type=png assets/store/screenshots/01-welcome.png
```
