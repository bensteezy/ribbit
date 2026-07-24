# ribbit notch agent monitor plan

## decision

Build the notch monitor as a native Ribbit surface over the agent system that
already exists.

```text
Codex / Claude / Cursor events
        ↓
RibbitAgentMonitor
        ↓
AgentNotchProjection
        ↓
RibbitNotchController + RibbitNotchView
        ↓
AppModel.focusAgentSession(_:)
```

Noot is the owned implementation donor. Its notch geometry, panel lifecycle,
hover state machine, dismissal policy, and jump-back behavior are the starting
point. Vibe Island is the interaction-quality benchmark: a nearly invisible
compact state, one continuous black surface when expanded, responsive
hover/click behavior, precise focus return, and motion that feels attached to
the display rather than presented as a popover.

Ribbit will not import, inspect, or reproduce Vibe Island code or assets.

## scope

The first release will:

| Area | Outcome |
| --- | --- |
| Compact notch | Ribbit frog activity mark on the left; live/attention count on the right |
| Expanded panel | Up to five prioritized sessions with project, activity, provider, and state |
| Attention | Permission/question/plan detail with an action that opens the exact source session |
| Focus | A row click switches to the matching Ribbit project and terminal, or routes to the external app |
| Dismissal | Hide a session until it enters a new live phase or produces new attention |
| Display support | Physical-notch geometry on supported MacBooks; top-center floating fallback elsewhere |
| Settings | Enable, hover expansion, auto-collapse, reveal dwell, display target, and activity-detail controls |
| Accessibility | Reduced motion, semantic labels, keyboard collapse, and visible focus for explicit keyboard mode |

This release will not add in-notch permission approval, question replies,
usage-metering, remote SSH sessions, or sound packs. Those require additional
provider return channels and are separate features. The notch remains a
monitor and jump-back surface.

## what the research found

### Ribbit already owns session truth

`RibbitAgentMonitor` already merges local Codex, Claude, and Cursor session
files with hook events. It assigns sessions to terminals, persists bridged
state, detects ready/attention transitions, and refreshes on a four-second
fallback timer. `AppModel.focusAgentSession(_:)` already switches projects,
selects the correct terminal, restores terminal focus, and routes unmatched
sessions to Codex or Cursor.

The notch must subscribe to this monitor. It must not create another scanner,
loopback bridge, timer, hook installer, notification engine, or focus router.

### Noot provides the owned implementation base

The useful Noot boundaries are:

| Noot code | Ribbit treatment |
| --- | --- |
| `OverlayWindowController` | Refactor into a Ribbit-owned panel controller |
| `TopAttachedIslandSurface` | Port and tune for Ribbit geometry |
| `NootStore` hover/expand state | Extract into a presentation state machine |
| `SessionDismissalPolicy` | Port with Ribbit agent model names and storage paths |
| `NotchSessionRow` and attention detail | Recompose with Ribbit tokens and frog identity |
| Noot session scanners/bridge/focus router | Do not port; Ribbit already has these |
| Noot accessory-app lifecycle and menu-bar fallback | Do not port; Ribbit stays a regular terminal app |

Noot already handles several hard parts correctly: pixel-aligned top anchoring,
physical-notch measurement, a nonactivating floating `NSPanel`, 60–120 Hz
display-link timing, delayed content reveal, reduced motion, hover pinning, and
rearming dismissed sessions after a real lifecycle change.

### Vibe Island supplies the quality bar

The installed Vibe Island 1.0.42 was inspected in compact, expanded-idle,
General settings, Display settings, and Shortcuts settings.

The interaction language to adopt is:

| Observation | Ribbit interpretation |
| --- | --- |
| Compact UI is almost entirely hidden by the hardware notch | Show only the frog/status wings; no extra pill below the housing |
| Expanded UI is a single black top-attached surface | No popover arrow, detached card, glass dashboard, or nested outer shell |
| Hover expansion defaults to 0.15 seconds | Use a short deliberate hover delay, not instant accidental expansion |
| Mouse-leave auto-collapse and five-second auto-reveal dwell | Support ephemeral and pinned-open modes separately |
| Clean and detailed compact modes | Ship clean first; keep the projection able to add detailed mode later |
| Panel width, height, content size, display target are configurable | Add essential settings now without reproducing Vibe Island's settings UI |
| Session switcher supports arrows, Enter, Escape, and a global shortcut | Make keyboard navigation a planned second slice after mouse behavior is proven |
| The overlay does not activate the host app on hover | Hover must never remove keyboard focus from a terminal or editor |

Official Vibe Island material also documents a nonactivating overlay, a
top-center fallback on displays without a notch, exact terminal jump, and
multi-display behavior:

- <https://vibeisland.app/>
- <https://vibeisland.app/multi-agent/>
- <https://vibeisland.app/changelog/>

## product state model

The monitor has four semantic states and three presentation modes.

### Semantic state

| State | Priority | Compact treatment | Expanded treatment |
| --- | ---: | --- | --- |
| needs you | 0 | Red frog/count treatment | One attention session plus its detail and open action |
| waiting | 1 | Red attention treatment | Same as needs you |
| running | 2 | Animated mint frog and running count | Live activity text |
| ready | 3 | Static blue/quiet frog and ready count | “ready” row with last-updated context |

Idle and completed sessions do not appear.

### Presentation mode

| Mode | Entry | Exit |
| --- | --- | --- |
| compact | Default | Hover delay, click, keyboard shortcut, or attention reveal |
| expanded ephemeral | Hover or automatic attention reveal | Mouse leave, dwell timeout, Escape, or optional outside click |
| expanded pinned | Click compact island or explicit keyboard open | Click compact/close control, Escape, or session selection |

The state machine, not individual SwiftUI views, owns these transitions. A
session refresh must not restart an in-flight geometry animation unless the
target size actually changes.

## interaction contract

| Input | Required result |
| --- | --- |
| Hover compact for 150 ms | Expand ephemerally without activating Ribbit or changing the key window |
| Leave expanded panel | Collapse after 500 ms unless pinned or pointer re-enters |
| Click compact | Expand and pin open |
| Click session row | Route to its exact Ribbit/external session, then collapse |
| Click row × | Hide the session without killing the agent or terminal |
| New attention event | Restore a hidden session, expand for the configured dwell, and preserve the current app's focus |
| Escape | Collapse only the notch; never send Escape to the previously focused terminal |
| Right click | Ribbit monitor settings and “hide monitor”; no destructive commands |

The row × means “hide from the monitor,” not close, terminate, unpin, or delete.
Its tooltip and accessibility label must state when the session will return.

## window and display architecture

Create a borderless, transparent, nonactivating `NSPanel` above normal windows.
It joins Spaces and can appear beside full-screen apps according to the user's
setting. `becomesKeyOnlyIfNeeded` stays enabled.

Geometry is calculated from the selected `NSScreen` on every presentation:

1. A physical notch exists when `safeAreaInsets.top` is nonzero and both
   auxiliary top areas exist.
2. The hidden hardware width is the gap between the left area's maximum X and
   the right area's minimum X.
3. The compact frame is top-centered and ends exactly on the safe-area
   boundary.
4. The expanded frame stays top-anchored while width and height interpolate.
5. A non-notch screen uses the same surface as a compact floating bar below
   the menu bar.

Never cache `visibleFrame` or notch measurements across display changes.
Recalculate after display changes, resolution/scaling changes, wake, and
active-display changes.

The first display-target choices are:

| Setting | Behavior |
| --- | --- |
| built-in display | Prefer the MacBook display; fall back to main |
| main display | Follow the display currently designated as main |
| follow Ribbit | Use the screen containing Ribbit's key window; retain the last screen while Ribbit is inactive |

“Follow keyboard focus across every application” is deferred until its
Accessibility implications and focus reliability are explicitly tested.

## smoothness plan

Noot's display-link controller is the baseline, but it needs a measurement and
tuning pass rather than a blind copy.

| Concern | Planned treatment |
| --- | --- |
| Frame pacing | Drive geometry from the selected screen's display link and use its timestamps |
| Animation restarts | Ignore state refreshes when the target frame is unchanged |
| Pixel seams | Round size and origin to the screen backing scale; keep a two-point top bleed |
| SwiftUI feedback | Disable hosting-view sizing and let AppKit own the window frame |
| Content timing | Resize the black silhouette first; crossfade content after a short delay |
| Easing | One no-bounce timing curve for AppKit geometry and SwiftUI content |
| Reduced motion | Snap geometry and use an opacity-only transition of at most 150 ms |
| Rendering work | Keep the compact frog canvas small and stop its timeline when no session is running |

The animation acceptance test is visual and instrumented: no frame target may
be reset by the four-second session refresh, and resize work must stay within
the active display's frame budget during repeated open/close cycles.

## lifecycle and ownership

Ribbit stays a regular dock app. The notch is an auxiliary window owned by an
application coordinator.

`RibbitApp` creates one `AppSettings`, one `AppModel`, and one notch
coordinator. Once configured, the coordinator lives beyond any individual
main-window view. Closing Ribbit's main window does not stop the monitor or
remove the notch. Quitting Ribbit stops the bridge and removes the panel.

`RootView.onAppear` will no longer be the only place that can start monitoring.
Monitoring moves to an idempotent application-lifecycle entry point so opening
multiple windows cannot create duplicate starts.

## settings

Add an `agent monitor` section to Ribbit settings:

| Setting | Default |
| --- | --- |
| show agent monitor in notch | on when a physical notch exists; otherwise off |
| expand on hover | on |
| hover delay | 0.15 s |
| auto-collapse on mouse leave | on |
| attention reveal dwell | 5 s |
| display target | built-in display |
| show activity detail | on |
| hide in full screen | off |

The settings UI remains lowercase and utilitarian. Advanced controls such as
panel width, maximum height, custom global shortcuts, sound, and per-agent
silence rules stay out of the first release.

## implementation slices

### 1. State projection and dismissal

Create a notch-only projection over `RibbitAgentMonitor.sessions`. It sorts by
Ribbit's existing state priority, excludes completed/idle sessions, applies
dismissal records, derives counts, and exposes primary attention.

Port Noot's dismissal rearm rules and add tests before any UI work.

Estimated effort: 0.5–1 day.

### 2. Panel, geometry, and motion

Create the nonactivating panel, notch/fallback geometry calculator, display
selection, display-change observers, and synchronized frame/content motion.
Render a black empty shell with the frog/count compact state.

Estimated effort: 1–1.5 days.

### 3. Session UI and focus routing

Add the expanded header, prioritized rows, attention detail, dismiss buttons,
hover/pinned interaction, Escape handling, and calls to
`AppModel.focusAgentSession(_:)`.

Estimated effort: 1–1.5 days.

### 4. Lifecycle and settings

Move monitoring startup to an app coordinator, make it idempotent, persist
notch preferences, support closing the main window, and add the settings
section.

Estimated effort: 0.5–1 day.

### 5. Verification and release polish

Run automated geometry/state/focus tests, the real multi-agent workflow,
Instruments frame checks, reduced-motion checks, Spaces/full-screen checks,
multi-display checks, relaunch checks, and the public-source/release gates.

Estimated effort: 1–1.5 days.

Total: approximately 4–6 focused engineering days.

## exact file plan

No production files are changed by this planning pass.

When implementation is approved, create:

| File | Responsibility |
| --- | --- |
| `Sources/Ribbit/AgentNotchModels.swift` | Projection, presentation state, dismissal records/policy |
| `Sources/Ribbit/AgentNotchGeometry.swift` | Screen selection, physical-notch and fallback geometry |
| `Sources/Ribbit/AgentNotchController.swift` | `NSPanel`, display observers, lifecycle, frame animation |
| `Sources/Ribbit/AgentNotchView.swift` | Compact frog wings, expanded rows, attention detail, controls |

Modify:

| File | Change |
| --- | --- |
| `Sources/Ribbit/RibbitApp.swift` | Own/configure the notch coordinator and start monitoring once |
| `Sources/Ribbit/AppModel.swift` | Expose only the minimal focus/current-session signals needed by the projection |
| `Sources/Ribbit/AppSettings.swift` | Persist notch behavior and add the settings section |
| `Sources/Ribbit/AppTheme.swift` | Add semantic running/ready/attention colors only if existing tokens are insufficient |
| `Sources/Ribbit/FrogPixelArt.swift` | Add compact working/resting poses without changing the app icon |
| `Tests/RibbitTests/RibbitTests.swift` | Add the complete state, dismissal, geometry, lifecycle, and focus suite |
| `README.md` | Document the feature after it passes the release gate |

No files are deleted. `Package.swift` should not need a change because SwiftPM
discovers source files in the target directory. No Vibe Island license,
binary, asset, or notice is added.

## automated acceptance tests

| Layer | Required coverage |
| --- | --- |
| Projection | Priority ordering, count derivation, five-row cap, primary attention |
| Dismissal | Ordinary activity stays hidden; inactive-to-live and new attention rearm |
| Presentation | Hover delay, re-entry cancellation, pinned mode, dwell, Escape |
| Geometry | Notched/non-notched, Retina rounding, display change, top anchoring |
| Lifecycle | One monitor/bridge start across view recreation; panel survives main-window close |
| Focus | Matching Ribbit terminal, project switch, external Codex/Cursor route, no route for dismissed row |
| Accessibility | Reduced motion, semantic labels, keyboard order, no focus theft on hover |
| Performance | Repeated open/close while session refreshes do not restart unchanged animation targets |

## hands-on workflow acceptance

The feature is not complete until this real workflow passes:

1. Start two Codex terminals, two Claude terminals, and one Cursor session in
   different Ribbit projects.
2. Keep typing and editing in one terminal while the notch expands on hover;
   verify the terminal remains the key input target.
3. Move agents through running, ready, question, and permission states; verify
   ordering, color, dwell, and dismissal rearm.
4. Click every session from another Space and from canvas/tab views; verify the
   exact project, tab, terminal, or external app receives focus.
5. Repeat on the built-in display, a non-notch external display, full screen,
   reduced motion, app relaunch, and with Ribbit's main window closed.

## release boundary

The first shippable milestone is reached when the monitor is useful without
being interactive beyond jump-back:

```text
see state → identify project/agent → click → land in the exact session
```

Direct approvals and answers remain blocked until a provider adapter can prove
that the action reaches the originating request exactly once, returns a
verifiable result, and cannot silently change a provider permission mode.
