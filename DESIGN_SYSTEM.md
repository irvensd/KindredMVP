# Design continuity

The existing semantic Paper, Ink, Plum, Rose, Sand, Surface, Secondary and OnPlum assets are unchanged, as are SF typography, the leaf mark, rounded editorial cards, native sheets, large photography and the four-tab floating navigation. No solid tab bar, replacement navigation, card stack or compensating Discovery padding was added.

Refinements:
- Photo arrows crossfade on Discover and animate native paging on full profiles. Current-photo labels, explicit controls and custom accessibility actions accompany the images.
- Profile changes use a restrained horizontal offset and opacity transition; swipes retain spring cancellation, deliberate commit thresholds and independent vertical scrolling.
- Prompt cards keep their editorial form, add header semantics and use sparkle/checkmark feedback with repeat likes disabled.
- The mutual-match screen uses ivory/plum, two circular portraits, a brief scale entrance and clear Say hello / Keep discovering actions. It scrolls at larger text sizes. Custom motion is suppressed for Reduce Motion.
- Message bubbles retain their original colors, shapes and alignment. Date headings, sender-aware previews, optional prompt ideas and a persistent composer improve context.
- The Your story screen retains its card structure. An optional, dismissible checklist supplies specific editing suggestions without requiring private disclosures.

Local prototype disclosures remain visible. Semantic asset contrast and screenshots do not establish full accessibility conformance; see the verification report for actual checks.

Accessible-size screenshot findings led to stacked radius labels, a shorter preference title, vertically arranged match portraits and a text-only Say hello button. Normal-size layouts remain the same.

## Discovery preference refinement

Age selection keeps native one-year steppers, with a plum combined-range summary and the original native minimum/maximum labels. Radius uses a leading-aligned “Within … miles” summary, a native five-mile slider with endpoint labels, and native five-mile stepper buttons in preferences. Onboarding shares the summary and slider but omits the extra stepper. Text wraps vertically at accessibility sizes; values use monospaced digits. No custom animation or navigation changes.
