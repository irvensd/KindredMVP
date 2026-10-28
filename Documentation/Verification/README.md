# Verification evidence

- `full-test-summary.json`, `full-tests.log`: complete final-application run, 38 passes / 1 native-title accessibility finding / 0 skips. Includes 25 passing unit tests.
- `accessibility-regression-summary.json`, `accessibility-regression.log`: passing rerun of the full remaining preference/chat accessibility scenario after a test-only exception for the native Preferences title. No app source changed. No runtime warnings in this rerun.
- `native-title-audit-capture.png`: inspected complete native title which the simulator audit flagged as clipped. The exception applies only to that element label and text-clipped audit type; other findings still fail the test.
- `baseline-regression-summary.json`, `baseline-regression.log`: deliberately failing baseline regression proving that new empty matched chats were sorted behind old chats before the fix.
- `changed-files.json`: source changes compared with the last tested Phase 1 copy.
- `source-sha256.json`: exact delivered project, source, tests and bundled assets.

The JSON summaries are unmodified xcresulttool exports. Results should be read together, not described as a clean 39-test single run. The seven text-entry layout warnings in the complete run remain unresolved; no functional test failed because of them.

**Release build: succeeded**, targeting generic iOS Simulator with the same project and Swift 6 language mode. `release-build.log` records the result. App Intents metadata notices are nonblocking.

## October 18 photo navigation

`photo-navigation-build.log` and `photo-navigation-test-build.log` record successful generic simulator builds. `photo-navigation-tests.log` records a blocked UI run (zero tests executed) because Xcode 27.1 requires CoreSimulator 1174.9.2 and the installed version is 1171.7.0. The new UI tests are compiled, not passed. Initial Discover screenshots were captured from the current app launched directly on the existing iOS 26.1 simulator; they establish static appearance only. See the latest report section for exact limits.

## October 18 personal interest

`personal-interest-summary.json` and `personal-interest-tests.log` record the final successful run: 37 unit and eight UI tests (45/45), zero failures/skips/runtime warnings. This includes the previously blocked photo-navigation scenarios. The initial 41/43 run and its Discover hierarchy are retained as `personal-interest-initial-*`; child identifiers inherited the portrait identifier until an explicit accessibility container was added. The final run follows that correction and the saved-label contrast adjustment. See the latest report section for exact coverage and limits.

## Compact completed story

The initial run passed two UI scenarios and recorded a SIGTERM in the layout/dismissal runner. The affected scenario passed on rerun, then passed again after a test-only change to fully reveal the large-text summary for its screenshot. The app source is identical across those runs. The initial name-field interaction repeated the known negative-frame runtime warning; both layout reruns report no runtime warnings. See the final report section and `compact-story-*.json`/logs for the separate results.


## October 19 discovery preferences

The `preferences-*` summaries and logs preserve the initial 41/43 and second 42/43 runs plus focused diagnostic attempts. The age-section clipping audit has an unresolved nil-element finding at standard and largest text sizes. Native labels, native steppers and scrolling did not eliminate it. Screenshots are retained for visual review. The final appearance test audits descriptions in all modes; the separate existing preferences/chat scenario still audits clipping at its radius position with the historic native-title exception. Do not describe scoped passing tests as a clean full accessibility audit. The known negative-frame warning recurred during onboarding name entry in broad runs.

October 27: `preferences-oct27-*` records a passing corrected filtering scenario, and `preferences-final-appearance-*` records passing final appearance/description checks with no runtime warnings. The interrupted screenshot run is retained separately. The earlier delivery run is available as a log only because its temporary result bundle was cleared.
