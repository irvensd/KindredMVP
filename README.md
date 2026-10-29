# Kindred · Phase 1.5

A native Swift 6 / SwiftUI iPhone prototype, minimum iOS 26. Open `Kindred.xcodeproj`, select the shared **Kindred** scheme and an iOS 26+ iPhone simulator, then press ⌘R. No signing team, package installation, backend, credentials or remote assets are needed for the simulator. Press ⌘U to run unit and UI tests.

The existing plum/ivory editorial design, large photography, four native tabs and floating translucent navigation remain intact. This phase refines discovery, mutual-match presentation, chats and optional profile completion.

## Try the experience
1. Complete the four-step onboarding, or choose **Already have an account? Sign in → Explore the demo**. Sign-in is explicitly a prototype preview.
2. In Discover, use the compact photo navigation pill: plum arrows flank the current photo count, with unavailable directions dimmed. Photo changes use a restrained directional fade; Reduce Motion removes the custom animation. Single-photo profiles omit the navigation control. On a full profile, native photo paging remains available. On Discover, swipe left for Next or right to save interest. Short slow drags return smoothly; deliberate quick flicks also work. Vertical-first and ambiguous diagonal drags stay reserved for scrolling. A release cue marks the distance threshold, and Reduce Motion keeps the photo stationary. The floating actions offer the same operations without gestures. Undo restores only the last skip. The compact action panel reserves a secondary Undo space so Next and I’m interested stay in place; larger text uses a labeled stacked layout.
3. Choose **Like this photo** beneath the current photo or **Like this answer** on a prompt to save what caught your attention. The confirmation names the member and item; **Your likes** keeps the photo or quoted answer. General interest remains available through the floating button or a right swipe. Each item saves once, and no action sends a message.
4. Amara and June have preloaded incoming likes. Showing interest in either creates one mutual match and opens the celebration. **Say hello** opens that member's existing demo chat; **Keep discovering** returns to Discover. Repeat likes do not create another match or celebration.
5. A conversation idea quotes an existing prompt and fills an editable draft. It never sends automatically. Replacing a nonempty draft requires choosing **Use suggestion**. Messages are stored only in the session and receive no generated replies or delivery receipts. Unsent drafts stay with each conversation when you navigate away; sending clears that draft, and process relaunch clears all drafts.
6. In You, edit and save your story, or preview the saved public profile with its privacy settings. When all three optional story sections are present, the checklist becomes a compact, dismissible summary. Incomplete stories keep the guidance and editing shortcut. Neither state requires faith or lifestyle disclosures.
7. Discovery preferences show the combined age range above one-year minimum/maximum adjustments. Radius shows “Within … miles,” with a slider and exact five-mile buttons. Save applies gender, adult age range and synthetic radius filters. Cancel leaves the previous values unchanged. Preferences survive tab changes and reopening the sheet, but reset when the process restarts.

## Command line
```sh
xcodebuild test -project Kindred.xcodeproj -scheme Kindred \
  -destination 'platform=iOS Simulator,name=Kindred QA' \
  -derivedDataPath /private/tmp/KindredPhase15Build \
  -collect-test-diagnostics never
```
Use an available simulator name or ID on your machine. Verified results and precise coverage are in `PHASE_1_5_REPORT.md` and `Documentation/Verification`.

All members, incoming activity and messages are fictional. All changes, including imported photos, reset on process relaunch. There is no Supabase, authentication, payment, live messaging or production matching. Debug-only launch arguments `--demo`, `--large-text`, `--dark` and `--reduce-motion` support repeatable UI checks; Release builds ignore them.
