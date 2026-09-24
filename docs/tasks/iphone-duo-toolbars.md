# iPhone Duo toolbar priorities

Assignee: unassigned
State: backlog — blocked on a Duo-capable simulator runtime (see Blockers)
Requested by: owner (2026-09-24)
Related: [project-state.md](../planning/project-state.md) open items 9 and 13

## Goal

Every screen keeps its important bar controls reachable on iPhone Duo, where the system can
present navigation bars and toolbars vertically on the side of the display (outer display when
closed; trailing views and sheets on the inner display). Rank each toolbar's items so the
system keeps the right ones visible and moves the rest to the overflow menu.

## Rules this task applies

From Apple's
[Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
("Organize bar items"):

- A vertical bar shows items as icons. An item with only a title, or with a custom view instead
  of a title or icon, is not presented vertically.
- Horizontal presentation prefers the icon; the overflow menu shows icon and title. Give items
  both an icon and a title for the most adaptability.
- Reserve the top of a vertical bar for navigation (Back, Close), then prominent actions (Done):
  `cancellationAction` for a custom Close, `topBarPinnedTrailing` for a prominent Done.
- `visibilityPriority(_:)` orders which items go to the overflow menu; `ToolbarOverflowMenu`
  puts items there directly; `axisBehavior(_:)` controls inclusion in vertical layouts.
- Sheets on the outer display present their bars vertically by default
  (`toolbarVerticalBehavior(_:)` opts out).

## SDK availability (checked 2026-09-24 in the SwiftUI interface files)

The app builds with Xcode 27.0 (iOS 27.0 SDK, deployment target 27.0), the same as CI
(ADR 0003).

| API | Xcode 27.0 SDK | Xcode 27.2 beta SDK |
|---|---|---|
| `visibilityPriority(_:)`, `ToolbarItemVisibilityPriority.low/.high` | yes (iOS 27.0) | yes |
| `ToolbarItemPlacement.topBarPinnedTrailing` | yes (iOS 27.0) | yes |
| `ToolbarOverflowMenu` | yes | yes |
| `ButtonRole.confirm`, `.close` | yes | yes |
| `axisBehavior(_:)` | no | yes |
| `toolbarVerticalBehavior(_:)`, `toolbarVerticalEdge` | no | yes |

A fix limited to the first four rows builds on CI today. The last two need CI on an Xcode 27.1+
image, which GitHub does not offer yet (open item 6).

## Toolbar inventory and findings (static audit, not yet seen on a Duo)

| # | Screen | Item | Today | Duo risk | Proposed rank / change |
|---|---|---|---|---|---|
| T1 | Cart | Members button with count, opens family management (`ShoppingListView.cartToolbar`) | Custom `HStack` label: `person.2` icon + count, so the count survives the icon-only collapse | High: a custom view is not presented vertically, so the cart's only toolbar action disappears on the closed outer display and in vertical trailing bars. Invite and family management remain reachable from the Settings tab | Priority `.high`. Rebuild as an icon + title item (title "Family"/"Семья", count as accessibility value or a badge). Owner decision: the count visible in the bar today would no longer show on regular iPhones unless a badge on the toolbar button works; verify `.badge(_:)` on the item content first |
| T2 | Cart | Sync spinner (`cart.updating`) | Custom `ProgressView` with `.sharedBackgroundVisibility(.hidden)` and a fixed `ToolbarSpacer` | Low: a status indicator; being dropped from a vertical bar loses nothing actionable | Priority `.low`; accept that it is hidden vertically. Check the fixed spacer does not leave an empty slot in a vertical bar |
| T3 | Home (shell before the cart loads) | Sync spinner | Custom `ProgressView` | Low, as T2 | Priority `.low` |
| T4 | Settings → display-name and cart-name sheets (`AccountRows` text-entry sheet) | Cancel (`cancellationAction`) and Save (`confirmationAction`) | Title-only buttons | High: a sheet on the outer display gets vertical bars by default, and a title-only item is not presented vertically, so the sheet may lose its only Save control. Where the system puts such items (overflow or nowhere) must be seen in the simulator | Cancel: `Button(role: .cancel)` or `.close` with an icon, top of the bar. Save: icon + title with `role: .confirm`, placement `topBarPinnedTrailing`, priority `.high`. Alternative with the 27.2 SDK only: `toolbarVerticalBehavior` to keep this small form's bar horizontal |
| T5 | History, History day, Settings | Navigation title and the system Back button | No custom items | None expected; the system adds Back | Check only |
| T6 | Member name prompt sheet (`MemberNamePromptView`) | In-content Save / Not now buttons, no toolbar | Not bar items | Bars not involved; check the `.medium`-style layout around the hinge only | Check only |

## Blockers

1. **Simulator runtime.** The `iPhone Duo` device type (`iPhone19,4`) declares
   `minRuntimeVersion 27.1.0`. Installed runtimes are iOS 26.5 and 27.0, so
   `simctl create … iPhone-Duo … iOS-27-0` fails with `SimError 403 Incompatible device`, both
   under Xcode 27.0 and under Xcode 27.2 beta (`27B5019j`, ships `DeviceHub.app`). The iOS 27.2
   runtime `24B5084k` (downloaded again on 2026-09-24) fails the same way: its
   `supportedDeviceTypes` lists iPhone 11 through iPhone 18 Pro Max, iPhone Air and the SE models,
   but not iPhone Duo, so the device type's `minRuntimeVersion` is necessary but not sufficient.
   Unblock: a runtime build that lists iPhone Duo among its supported device types (check with
   `xcrun simctl list runtimes -j`), expected with a later Xcode 27.1+/27.2 seed or GA; whether
   Device Hub offers the Duo with the current runtime is unchecked.
2. **Owner decision for T1:** keep the member count in the cart bar (badge, if it works on a
   toolbar item) or drop it in favour of an icon + title item.

## Acceptance

- On an iPhone Duo simulator, closed (outer display) and open (inner display, including a
  trailing sheet), for the cart, Home, History, History day and Settings screens and both text-entry
  sheets: every navigation and confirmation control is visible in the bar or in the overflow
  menu, the members action stays in the bar, and spinners may be hidden.
- On a regular iPhone (CI simulator), the bars look as before apart from the approved T1 change.
- UI smoke tests that tap `cart.members` or the sheet buttons still pass; a REQ ID covers the
  ranking if a requirement is added (proposal: under `REQ-SHELL-*`, owner approval needed).
- `just verify` passes.

## Verification plan

1. Unblock the runtime (Blocker 1), create the Duo device, run the Debug build with the demo data
   (`just demo role=owner`), and screenshot every screen in closed, open and half-open poses
   before any code change. Record which items the system dropped or moved.
2. Apply the T1–T4 changes that the screenshots justify, one commit per screen.
3. Repeat the screenshots, then run `just verify`.
