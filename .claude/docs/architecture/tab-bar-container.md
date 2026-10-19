# Tab Bar Container

The bottom tab bar is SwiftUI inside a thin UIKit shell. SwiftUI draws the bar row, the center control, the center panel and the shelf. UIKit keeps the three jobs that need a `UIViewControllerTransitionCoordinator` or a `UIView` hit test: the fold, the passthrough hit testing, and the resting bottom clearance that content is inset by. The reasoning is in [ADR 0001](../../../docs/adr/0001-uikit-shell-around-swiftui-tab-bar.md).

`MainTabBarViewController` is a plain `UIViewController`. It mounts one child at a time, owns the top status strip, and writes the bottom insets on the tab and content controllers.

## Model in brief

- The bar row has four fixed slots around a center hole. Slots select tabs or open the shelf.
- The center control sits in the hole and morphs into the center panel. Every size is read from one progress value between 0 and 1.
- One value, `TabBarPanelKind?`, says which panel is open: `.shelf` or `.content(.scan)`. The shelf and the center panel cannot both be open.
- One value, `TabBarVisibilityState` (`shown`, `folded`, `hidden`), says where the bar sits. The fold controller animates it.

## Ownership

```
MainTabBarViewController            container, status strip, widget and inset layout, SPAHosting
├── TabBarContainer                 mounts one tab or one SPA
├── ChainConnectionStatusBarView    20 pt strip, informational only
└── TabBarBottomChromeController    bar, panels, fold, outside tap, bar items
    └── TabBarChromePassthroughView full-bleed, hit tests only the grab zone and the outside-tap area
        └── TabBarChromeSurfaceView fold transform target, bar layout
            └── TabBarBarHostView   accepts touches in the bar row and the open panel's rise
                └── UIHostingController<TabBarBarView>
                                    SwiftUI bar row, center control, shelf
```

## Where Things Live

| Thing | Location |
|---|---|
| Container controller | `polkadot-app/Modules/MainTabBar/MainTabBarViewController.swift` |
| Widget and inset layout | `polkadot-app/Modules/MainTabBar/MainTabBarViewController+Widgets.swift` |
| SPA hosting | `polkadot-app/Modules/MainTabBar/MainTabBarViewController+SPA.swift` |
| Child mounting | `polkadot-app/Modules/MainTabBar/Container/TabBarContainer.swift` |
| Tab-vs-SPA selection | `polkadot-app/Modules/MainTabBar/Container/TabBarContentSelection.swift` |
| `hidesBottomBarWhenPushed` resolution | `polkadot-app/Modules/MainTabBar/Container/TabBarHiddenPolicy.swift` |
| Re-tap behaviour | `polkadot-app/Modules/MainTabBar/Container/TabBarReselectionPolicy.swift` |
| Scroll-to-top target search | `polkadot-app/Modules/MainTabBar/Container/TabBarScrollToTopLocator.swift` |
| Bottom chrome: bar, panels, fold, clearance | `polkadot-app/Modules/MainTabBar/Chrome/TabBarBottomChromeController.swift` |
| Chrome apply input | `polkadot-app/Modules/MainTabBar/Chrome/TabBarChromeContext.swift` |
| Passthrough hit testing | `polkadot-app/Modules/MainTabBar/Chrome/TabBarChromePassthroughView.swift` |
| Fold transform target, bar width | `polkadot-app/Modules/MainTabBar/Chrome/TabBarChromeSurfaceView.swift` |
| Fold state machine | `polkadot-app/Modules/MainTabBar/Chrome/TabBarFoldController.swift` |
| Fold state resolution | `polkadot-app/Modules/MainTabBar/Chrome/TabBarVisibilityPolicy.swift` |
| Fold drag decision | `polkadot-app/Modules/MainTabBar/Chrome/TabBarFoldDecision.swift` |
| Panel state machine | `polkadot-app/Modules/MainTabBar/Chrome/TabBarPanelController.swift` |
| Panel kinds | `polkadot-app/Modules/MainTabBar/Chrome/TabBarPanelKind.swift` |
| Bar row view (SwiftUI) | `polkadot-app/Modules/MainTabBar/Chrome/TabBarBarView.swift` |
| Bar row state | `polkadot-app/Modules/MainTabBar/Chrome/TabBarBarViewModel.swift` |
| Shelf content (SwiftUI) | `polkadot-app/Modules/MainTabBar/Chrome/TabBarShelfView.swift` |
| Slots | `polkadot-app/Modules/MainTabBar/TabBarSlot.swift`, slot list in `MainTabBarPresenter.swift` |
| Slot-to-tab index mapping | `polkadot-app/Modules/MainTabBar/Chrome/TabBarSlotMap.swift` |
| Tab items | `TabBarItem` in `polkadot-app/Modules/MainTabBar/MainTabBarProtocols.swift` |
| Center panel height declaration | `polkadot-app/Modules/MainTabBar/Chrome/TabBarCenterContentHeight.swift` (`.fits(CGFloat)` or `.fill`) |
| Center panel content (scanner) | `polkadot-app/Modules/MainTabBar/ScanPanelViewController.swift`, `ScanPanelPlainViewController.swift` (chosen by `FEATURE_INPUT`) |
| Onboarding tips | `polkadot-app/Modules/MainTabBar/Chrome/TabBarTipController.swift`, `polkadot-app/Modules/MainTabBar/Tips/` |
| Floating widgets | `polkadot-app/Modules/MainTabBar/TabBarWidgetController.swift`, `MainTabBarFloatingWidgetStackView.swift` |
| Bar, center control, shelf container | `Packages/PolkadotUI/Sources/Components/DSTabBarShell/DSTabBarContainer.swift`, `DSTabBarCenterControl.swift` |
| Bar outline, morph shape, geometry | `Packages/PolkadotUI/Sources/Components/DSTabBarShell/DSTabBarShape.swift`, `DSTabBarMorphShape.swift`, `DSTabBarStyle.swift` |
| Bar material | `Packages/PolkadotUI/Sources/Components/DSTabBarShell/DSTabBarMaterial.swift`, `DSTabBarVariableBlur.swift` |
| Bar item and chip models | `polkadot-app/Modules/MainTabBar/Chrome/TabBarBarItem.swift` (`TabBarBarItem`), `TabBarShelfChip.swift` (`TabBarShelfChip`) |
| Bar icons | `Packages/PolkadotUI/Sources/Components/DSTabBarShell/DSTabBarConnectionGlyph.swift`, `DSTabBarTabsGlyphView.swift` |
| Top status strip | `Packages/PolkadotUI/Sources/Modules/MainTabBar/ChainConnectionStatusBarView.swift` |
| SPA tab store and controller pool | `polkadot-app/Modules/Browser/SPABrowserCoordinator.swift`, `polkadot-app/Modules/Browser/Pool/SPAControllerPool.swift` |
| SPA chip view models | `polkadot-app/Modules/MainTabBar/SPATabChipViewModel.swift` |
| `topmostViewController` | `Packages/UIKitExt/Sources/UIWindow/UIWindow+keyWindow.swift` |
| `mainTabBarController` | `polkadot-app/Common/Extension/UIApplication+MainContainer.swift` |

## Bar Row

`DSTabBarContainer` lays out two slots left of the center hole and two right of it. The bar row is a 62 pt tall capsule (`DSTabBarStyle.height`). Its bottom gap is the bottom safe-area inset minus 7 pt, at least 12 pt (`DSTabBarStyle.bottomGap(bottomSafeAreaInset:)`). The notch is cut from the bar's top edge: a bowl of radius 34 pt centred 22 pt below the top edge, 56 pt deep, whose shoulders meet the top edge 74 pt apart. The two inner slots stop at those shoulders. The bar row takes four `TabBarSlot` values, in the order the presenter lists them. Under `FEATURE_PRODUCTS` they are Chat, Pocket (`wallet`), Browse, and Apps (`.action(.spaTabs)`). Without it they are Chat, Pocket, Settings (`.tab(.settings)`), and Network (`.action(.connectionStatus)`). Network opens the shelf, which then lists the chain connections the connection status sheet shows, and funding products open as a modal sheet instead of a tab.

The row is an accessibility container with the tab-bar trait.

`DSTabBarStyle.rowWidth(inAvailableWidth:)` gives the bar row width. It is the available width minus 10 pt on each side, capped at 440 pt. The fold controller and the center panel sizing both use it.

**Center hole.** The center button is 64 pt (`centerButtonSize`). The bowl radius is derived as `notchRadius = centerButtonSize / 2 + notchRingGap`, which gives 34 pt with the 2 pt `notchRingGap`. The bowl center sits 22 pt below the top of the bar row (`notchCenterY`), so the center button stands 10 pt above the bar. The cutout is the brief's outline of six cubic curves, symmetric about the bar's centre line, positioned against the bar row. While the shelf is open, the part of the bowl's circle above the row is cut as well, so the resting button keeps its ring. `DSTabBarShape` and `DSTabBarShadowMask` subtract the same cut-out from the bar. The open center panel is `DSTabBarMorphShape`: a body with corner radius up to 32 pt and an 88 × 31 pt lobe under its bottom edge, narrowed in proportion while the panel is narrower than 88 pt. The center button's scan frame is `DSTabBarScanFrameShape`, four brackets on a 24-unit grid. The bar's rim strokes its outline with the brief's diagonal gradient and end wash, and a separate glint follows the cutout's edge. Its shadow is drawn from a plain pill silhouette with no notch. It is masked to outside the bar's outline (`DSTabBarOutsideMask`), and the notch is cut from it afterwards (`DSTabBarShadowMask`). Its top edge is pulled in by `barShadowTopInset` (2 × shadow radius − shadow y, 16 pt), so the falloff ends at the bar's top edge and no line shows across the notch. Its sides and bottom keep the 6 pt inset. It fades out while the center panel opens. All tab bar colours are local values in `DSTabBarStyle.Palette`.

**Selection pill.** `DSTabBarContainer` draws the pill behind the selected slot, from its `selectedSlot` parameter. It is an 80 × 54 pt capsule, white at 10 % with a white 8 % line along its top. It slides between slots over 238 ms on CSS ease (0.25, 0.1, 0.25, 1), and the slot icons change colour on the same curve. It snaps under Reduce Motion. The Apps slot never takes the pill. It reads as active through its color.

- A tab slot selects a tab. Taps are plain taps. There is no drag across tabs.
- The Apps slot opens the shelf. It shows the open-product count and reads as active while the shelf is open or a product is mounted.
- `TabBarSlotMap` converts between bar position (item index) and tab position (tab index). Only tab indices cross into `TabBarContainer`.
- Titles appear under the icons only when the interactor enables labels (`setLabels(visible:)`).
- While the bar is folded, a slot tap only unfolds the bar. It does not select.

## Center Control and Center Panel

The center control, `DSTabBarCenterControl`, sits in the hole. A tap opens the Scan state. An upward swipe on the button opens it straight into the Search state when the host provides the swipe callbacks (FEATURE_INPUT builds), and the Scan state otherwise. A downward drag or a tap closes it. A flick decides on its own, and otherwise the halfway point decides. The control's rim is two gradient strokes cross-fading on `openBlend`, rendered as a drawing group: SwiftUI rasterises gradient strokes on the CPU, and on a full-height morph that took about half of each frame. The bar and the control each have their own glass (`DSTabBarBarMaterial`, `DSTabBarCenterMaterial`): the variable blur at a per-surface intensity tuned by eye, under the brief's fills. As the panel opens past 20 % and up to 70 %, the control's fill turns to the panel's dark fill, and its rim changes from the button's to the bar's. While it opens, `DSTabBarDimLayer` dims the screen behind it, and the bar's items blur and fade while the bar rises 2 pt.

Every width, height and radius is read from one progress value, so the shape is valid at any point of a drag. Every open, close and Scan or Search state change runs on one 329 ms cubic ease-out (0.33, 1, 0.68, 1), in SwiftUI and in UIKit (`DSTabBarStyle.animateCenterChange`). The width follows a reshaped progress: it starts 4 % later and blends 35 % smoothstep with 65 % ease-out, so the panel stretches up before it widens. A drag starts after 10 pt, a touch under 14 pt is a tap, the drag travel is the open height less the button (at least 120 pt), and past fully open the panel stretches by a third of the finger's travel. On release the halfway point decides, unless a flick faster than 500 pt/s would cross it within 100 ms; the rest of the motion takes 2.5 × remaining distance / speed, within 180–420 ms, above 300 pt/s, and 340 ms otherwise. A grab mid-settle starts from the on-screen progress. During a drag the content (the scanner) and the grabber show from 88 % of the travel. A settle open shows the content and the grabber at once, with no delay, blur or rise: they ride the panel's top edge while the shape crops them. On a close the shape starts at once, and the content and the grabber stay shown and fade out together over the last 35 % of the close, starting at 30 % of it. The Search state's results list still fades in 224 ms after a state change, over 141 ms, unblurring from 8 and rising 8 pt. Under Reduce Motion the progress snaps and the content cross-fades over 220 ms; a close waits for that cross-fade before the shape snaps. The chrome builds the content the first time the control shows it, and the content is released when the control removes it.

**Settling.** The control reports open or closed to the chrome (`onSettled`) when its own settle animation completes. It does not report during a drag. A UIKit-driven move through `TabBarBarViewModel.setCenterPanelOpen` reports from the end of its animation. A drag past open stretches the panel by a third of the finger's travel, and a drag past closed clamps at closed; both commit only on release and settle. A cancelled drag settles to the nearer end.

**Accessibility.** VoiceOver sees the control as a button labelled by the caller. The app passes the `QR scanner` string. When the panel is open, the escape action closes it.

The panel declares its height rather than measuring the content. `ScanPanelViewController.declaredContentHeight(forPanelWidth:)` returns a `TabBarCenterContentHeight`. A fitted height comes from `ScanPanelViewLayout.declaredHeight(forWidth:)`, which owns the layout constants. The chrome takes the width from `DSTabBarStyle.rowWidth(inAvailableWidth:)` of its own view width, not from the hosting view, because the hosting view is laid out after the chrome and is 0 wide on the first pass. Measuring a live camera would start a second capture session. The chrome recomputes the height on layout and whenever the content reports a change.

**Search focus.** The scan panel's search field is always present. Focusing it puts the panel in the Search state: the panel fills the room above the bar, its top 12 pt below the top safe area. Focusing reports through `ScanPanelViewController.onSearchFocusChanged`; `MainTabBarViewController` passes that to `TabBarBottomChromeController.setBarHidden(_:)`, and `DSTabBarContainer`'s `isBarHidden` fades the bar row out (0.2 s ease) while the panel stays. The bar returns when focus ends. Closing or folding the panel also ends focus. A pan that begins on the search field stays with the field and does not move the panel.

While search is focused, the panel declares `.fill` instead of a height. The chrome caps the panel with `DSTabBarStyle.centerContentHeight(fittingRise:)` at `availablePanelHeight`, the room between the bar row and the bottom of the chain status strip. A filled panel's top meets the strip.

**Swipe into Search.** `DSTabBarCenterControl` takes two optional callbacks. `onSwipeOpenBegan` fires once per drag when a drag on the button that began short of fully open (at rest, or grabbing a panel still moving) moves up past the 14 pt tap slop; content drags from the open panel never fire it. `onSwipeOpenLanding` fires when that drag's release settles open and 60 % of the settle has run (at once under Reduce Motion, after the progress snaps). The package knows nothing about search or the keyboard. The model forwards both to `TabBarBottomChromeController`, which passes nil when the app sets no handler, so the plain arm keeps opening the Scan state. Under FEATURE_INPUT, `MainTabBarViewController` holds `isSearchSwipePending` (the scan panel controller may not exist yet when the swipe begins) and declares `.fill`, so the travel runs to the filled panel's top. `ScanPanelViewController.setSearchPending(_:)` shows the Search state layout without focus and keeps the camera off; the bar keeps the Scan state look. At the landing the chrome commits `.content(.scan)` first, so `currentKeyboardLift` sees the open scan panel when the keyboard frame changes, and then the host calls `focusSearch()`, which runs the normal focus path. `setCenterPanelOpen(true)` returns early because `centerProgress` already holds 1, so the release animation is not restarted. A close or a settle closed drops the swipe and calls `setSearchPending(false)`, which returns the panel to the Scan state's layout: the chrome reuses the content controller until a committed close, and a swipe that never landed open never commits one.

**Keyboard.** The keyboard lift has one owner, `TabBarFoldController.keyboardLift`, which the fold transform carries. `TabBarBottomChromeController` recomputes it on each keyboard frame change, animated with the keyboard's own duration and curve, and whenever a panel opens or closes. While the scan panel is open, the chrome lifts until the keyboard covers the center button's foot by `keyboardButtonOverlap` (4 pt). Any other keyboard, or a closed panel, leaves the chrome at rest. The lift shrinks `availablePanelHeight` by the same amount.

**Haptics.** The PolkadotUI components play SwiftUI sensory feedback next to the gestures that trigger it; the app chrome plays none. `DSTabBarCenterControl` plays a medium impact when a tap, a VoiceOver activation or a released swipe opens the panel; a swipe that starts and ends open plays nothing. A swipe plays nothing while it moves the panel, only its end haptic (user decision, overriding the brief's light haptic at swipe start). It plays a light impact on every close: when `progress` reaches 0 outside a drag, which covers the control's own settles and every host close, or on the release of a drag that already clamped the panel closed. `DSTabBarContainer` plays a medium impact when `isBarHidden` changes while `openProgress` is 1, so a Scan ↔ Search change is felt but a close from the Search state plays only the light close. A swipe into Search instead plays a medium impact each time the dragged panel crosses halfway, in either direction, and its release plays no end haptic (no medium on open, no light on return). The landing's focus hides the bar through `setBarHidden(_:playsFeedback: false)`, which sets the container's `playsBarHiddenFeedback`, so it adds none either. A simultaneous tap gesture on each slot plays a selection tick on every slot tap, a reselect included.

**Closing.** Before the close animation starts, the chrome calls `ScanPanelViewController.prepareForClose()`. It stops capture, then cancels the search. Ending search focus therefore does not restart the camera. `closeCenterPanel` calls it before it moves the progress, because the control removes content that a drag already hid as soon as the progress reaches 0, and that removal ends search focus. `applyCommittedPanel` calls it again; the second call does nothing. The control never removes content mid-drag: a drag held at closed leaves the removal to its settle, after `onSettled`. While search has focus, `setCaptureActive(true)` from a settle that re-reports open leaves the camera off.

**Search field and list.** The scan panel's field (`DSSearchRowView`), its scan button and the plain arm's `SearchContactFieldButton` draw the brief's field material, `DSTabBarFieldMaterialView`: white 6 % fill, a white 18 % line along the top and a 1 pt white 8 % outline. The field centres its 20 pt icon and placeholder in the Scan state and switches to a leading 22 pt icon in the Search state (`setSearchFocused`). It draws its own clear button (a 22 pt circle in a 32 pt touch area) and a #0a84ff caret. The results list, shared with the full-screen Search Contact screen, has flush 64 pt rows with no separators, uppercased section headers per source, and `DSSearchAvatar` for the 40 pt avatar with the 20/24 semibold initial, so the shared `DSAvatar` stays untouched. Colours live in `DSTabBarStyle.Palette`; the Inter styles with no exact design system match (header with 0.06 em tracking, 16/22 row name and query, 20 pt initial) live in `DSTabBarStyle.SearchTypography`.

**Preview attach.** Attaching or detaching `AVCaptureVideoPreviewLayer.session` on a running session reconfigures it on the main thread for 200–400 ms. Pausing capture (search focus, close) only hides the preview and stops the session; the layer stays attached, so a restart does not reconfigure. `EmbeddedQRScannerViewController` detaches once, when its view disappears: at once on a stopped session (about 10 ms), or after `AVCaptureSession.didStopRunningNotification`. A restart cancels that wait. `QRCaptureService` calls `stopRunning` only on a running session, because the presenter's and the service's `deinit` queue extra stops that could land inside the detach, which throws. The first attach happens before the session starts: `QRCaptureService` calls `qrCapture(service:willStart:)` through `DispatchQueue.main.sync` before `startRunning`, and the view attaches the stopped session (under 1 ms) without showing it. After the start, `configureVideoLayer` finds it attached and only fades the preview in. Nothing on the main thread may wait synchronously on the capture queue, or that `main.sync` deadlocks.

The center panel can also open from code. `ModuleNavigator.openScanPanel()` sets `.content(.scan)`, and the control follows through `setCenterPanelOpen`. Closing the panel from any source closes the control.

Under Reduce Motion the geometry snaps, and only the content cross-fades.

## Shelf

The Apps slot opens the shelf, which grows upward from the bar row. Its height is the content height, capped at the space between the bar row and the top safe area. Beyond the cap the grid scrolls.

- The top row holds a connection status icon and a settings icon. Neither is a tab. Connection status opens as a page sheet at the medium detent only. Settings opens as a modal navigation stack. Both close the shelf first. `MainTabBarWireframe` builds that stack through the injected `TabFactoryProtocol`. Opening device details while the Settings stack is the topmost presented controller pushes onto it.
- The grid holds one cell per open product. Tapping a cell mounts that product and closes the shelf. A long press reveals a close control. The cell's Close accessibility action does the same.

## Panels

`TabBarPanelKind` is `.shelf` or `.content(TabBarAction)`. Because the shelf and the center panel are one value, opening one closes the other.

`TabBarPanelController` runs the transition. Tapping a different action closes the open panel, then opens the new one when the close completes. Tapping the open panel's own action closes it.

The open panel closes on:

- a tap outside the open panel (`isOutsideTapEnabled` on the passthrough view),
- a tab selection,
- a connection status or settings tap,
- a product tap,
- any fold state other than `shown`.

## Hit Testing and Bar Rise

UIKit stops hit testing at a view's bounds, so `TabBarBarHostView` is sized to the full room above the bar at rest, which holds any open panel. It never resizes for a panel. Its `liveHeight` sets the region that accepts touches: the bar row plus a rise. The row stays at the bottom. The rise is the taller of two values: `DSTabBarStyle.centerButtonRestingRise` (10 pt), which keeps the resting centre button touchable, and the open panel's rise. The open panel's rise is `DSTabBarStyle.centerPanelRise` for the center panel, or the shelf's content height capped at the available height for the shelf. The rise is set when the panel state commits and is not animated. The live region is set as soon as the bar is installed. The SwiftUI springs animate what is drawn inside it.

`TabBarChromePassthroughView` claims a touch in only two cases: the folded grab zone, and the dismiss area while a panel is open. Every other touch goes to the content behind the chrome. `TabBarChromeSurfaceView` returns nil for hits on its own empty area. `TabBarBarHostView` accepts touches in its live region.

The fold pan recognizer starts only on the bar row outside the center hole, and only for a drag that leads horizontally. It does not start on a tab root or while the bar is `hidden`.

## Fold

The three states are `shown`, `folded` and `hidden`.

- **Shown.** The bar sits at the bottom of the screen.
- **Folded.** The bar slides to the leading edge and leaves a 19 pt sliver. A 44 pt grab zone on the passthrough view restores it on tap.
- **Hidden.** The bar slides fully off the leading edge. There is no sliver and no grab zone, so tab navigation is not available on that screen. The only conformer to `TabBarChromeVisibilityCustomizing` in the app is `ChatViewController`.

`TabBarVisibilityPolicy.state(isTabRoot:derived:override:)` resolves the state in this order:

1. A tab root is always `shown`. A tab root never folds.
2. A per-screen user override (`folded` or `shown`) wins.
3. Otherwise the derived state applies.

Without `FEATURE_PRODUCTS`, every screen other than a tab root is `hidden`.

The derived state comes from `TabBarHiddenPolicy.deriveFoldState(in:showing:)`. It is `hidden` when the target opts out. It is `folded` when any controller above the root, up to the target, sets `hidesBottomBarWhenPushed`. The root is excluded, so a tab root that sets the flag does not fold.

Overrides are stored per screen, weakly keyed on the navigation screen, so folding one pushed screen does not affect another. The fold controller ignores override requests while the bar is `hidden`.

**Interactive pops.** The transition coordinator drives the fold. `setInteractiveTarget` runs inside `animate(alongsideTransition:)`. When the interaction ends, the chrome commits the incoming screen's state. If the pop was cancelled, it commits the staying screen's state, rebuilt with `TabBarHiddenPolicy.stackAfterCancelledPop`.

**Animation.** A spring (duration 0.45, damping 0.85) takes the gesture's velocity as its initial velocity.

`TabBarFoldDecision` classifies the end of a horizontal drag on the bar row. From `shown`, a fast leftward flick folds the bar. Any other drag reads as a selection, which the bar takes no action on, so the bar stays shown. From `folded`, a tap or a fast rightward flick unfolds. Otherwise the bar unfolds if the drag passes 30% of the fold distance, and settles back to folded if it does not.

## Clearance and Safe Area

Two bottom insets stack, and they go on different controllers so they compose.

| Inset | Applied to |
|---|---|
| Bar clearance | the tab's `UINavigationController`, or the tab controller itself when there is none |
| Widget height | the top screen's controller, or added to the tab controller when there is no navigation controller |

The two change at different rates. The navigation controller is stable for the tab's lifetime, and the widget height follows the top screen. `updateContentSafeAreaInset()` zeroes the controller it inset last before it writes the new one.

- `restingBarHeight` is 83 pt (`DSTabBarStyle.restingHeight`) on a tab root. Elsewhere it is the raw bottom safe area.
- `restingBottomClearance` is `restingBarHeight` minus the bottom safe area, floored at 0.
- Clearance is contributed only on a tab root. A pushed screen that does not set `hidesBottomBarWhenPushed` reserves no space, so the bar floats over its bottom content and takes touches in its capsule. Such a screen should either set the flag or keep interactive content clear of the bottom.
- The shelf and the center panel overlay content. They do not change clearance.

**Recalculation.** Three events recompute the insets from `container.selectedController`: the container's safe area changes, the chrome's safe area changes, and a tab mounts. Re-deriving from the selected controller stops a late `didShow` from a background tab pinning insets to a screen that is not on screen.

**Fold inputs.** `isTabRoot`, the derived state and the screen change only through `applyChrome(_:animatingAlongside:)`. The inset path reads them but never writes them.

**No window.** `updateWidgetLayout` returns while the view has no window, so a `.fullScreen` presentation elsewhere does not produce bad insets. The last applied insets hold until the view reattaches.

## Top Status Strip

A 20 pt strip sits at the top of the container. It shows one ring per connection row. Each ring's accessibility label is the chain title and its state. No chain name is drawn. The strip has no tap handling, does not fold, and does not hide.

- `installStatusBar()` sets `additionalSafeAreaInsets.top` to 20 once, in `viewDidLoad`. Every mounted navigation controller passes that inset to the screens it pushes, so a pushed screen's top safe area already includes the strip.
- The strip paints no fill. The container's `.bgSurfaceMain` background shows behind the system status bar and the strip.
- `installStatusBar()` runs before `installChromeController()`, so the bar stays above the strip. Mounted children insert at index 0, so they sit below it.

## Mounting and Re-tap

`TabBarContainer` mounts one child at a time, full bleed into the container's view. A tab switch cross-fades over 0.15 s. The incoming view starts at scale 0.998. The outgoing view is removed when the fade completes. Non-animated mounts skip the fade.

A tap on the selected tab is a re-tap. `TabBarReselectionPolicy.action(for:)` checks these cases in order:

1. A modal is presented from the target: ignore.
2. The navigation stack is deeper than its root: pop to root.
3. Otherwise: scroll to top.

Scroll-to-top fires only at the tab root, so returning from a detail screen keeps the root's scroll position. `TabBarScrollToTopLocator` picks the scroll view by visible area, then vertical scrolling, then depth. A screen cannot nominate one.

While an SPA is mounted, a tap on the selected tab switches back to the tab. It is not treated as a re-tap.

## SPA Hosting

`TabBarContentSelection` is `.tab(Int)` or `.spa(UUID)`. An SPA is a peer of the tabs. It is not pushed onto a stack or presented over the container. `MainTabBarViewController` conforms to `SPAHosting`. `ModuleNavigator`, `ProductsNavigationRouter`, `SPAWireframe` and `ProductOpener` reach it through `UIApplication.shared.mainTabBarController`.

Opening a product:

1. `SPABrowserCoordinator.findOrCreateTab(for:)` matches on `dotDomain`. An existing tab with another page is navigated in place.
2. `SPAControllerPool` vends one `SPAViewController` per tab id.
3. `container.mountSPA(_:for:)` sets the selection to `.spa(id)` and cross-fades the controller in.
4. `applyChrome(.spa(controller))` sets `isTabRoot: false` and a derived state of `folded`. The bar folds and contributes no clearance.

`presentProduct(page:)` is the one-shot path for funding products. It presents a page sheet at 92% of the maximum detent. The product never enters the tab store, so closing it leaves no chip.

**Chips.** `MainTabBarInteractor` sends the open tabs to the presenter (`didReceiveSPATabs`). The presenter maps them through `SPATabChipViewModelFactory`, and the view passes them to the chrome as `TabBarShelfChip`. `applyChips()` runs on every mount and unmount, so the selected chip follows the mounted product.

**Unmounting.** `minimizeSPA()` returns to the last tab index. `closeSPA(tabId:)` drops the tab and minimizes only when that tab was mounted. The product game pill widget is detached while the product it counts down to is mounted.

## Adding a Tab

The bar has four fixed slots. `DSTabBarContainer` lays out exactly four slot views, so the count of tabs does not change the layout. To add a tab that fits in the existing four slots:

1. Add a case to `TabBarItem` with a localized `title` and an image.
2. Build its controller in `TabFactory.view(for:)`.
3. Add an entry to `AccessibilityID.Tab` so that `AccessibilityID.Tab.item(for:)` returns it.
4. Place the new slot in the presenter's slot list. Its position in the list is its position in the bar.

A fifth slot needs `DSTabBarContainer` to take a fifth view. Items past the fourth are not rendered, and a missing fourth item leaves a blank column.

## Gotchas

- **Tips on bar items do not show.** `TabBarTipController.anchorItem(for:)` returns nil for `.barItem` anchors, so only the status strip anchor can show a tip. The scan tip is anchored to `.action(.scan)`, which no bar slot uses.
- **Size the center panel from the chrome's width.** The hosting view is 0 wide when the chrome first lays out. A height computed from it starts the scan panel at the wrong size, and SwiftUI then routes the first taps on the embedded UIKit panel to its own host view, so the search field ignores them until the panel is reopened.
- **Two actions have no slot.** `TabBarAction.scan` and `TabBarAction.connectionStatus` have no bar slot. The center control and the shelf open them directly, so the branches for them in `handleAction` are not reached from a slot tap.
