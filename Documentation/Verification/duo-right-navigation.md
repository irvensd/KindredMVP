# Duo navigation decision — November 5, 2026

User approved the native right-side navigation on Duo. Removed the uncommitted bottom-navigation experiment; production navigation is restored to its existing implementation, preserving native bottom navigation on standard iPhone.

Validation: DuoRightNavigation.xcresult completed successfully on Kindred Duo QA (iOS 27.1). The retained testDuoRemainingScreens passed: four tabs, profile editor cancellation, conversation typing, Send availability, and Done keyboard dismissal. A temporary right-placement geometry assertion also passed and its screenshot was visually reviewed; that device-specific assertion was removed so ordinary iPhone suite runs do not require a right rail. Raw result and screenshots are in the project work directory outside the repository.

Folded/unfolded transitions remain unverified. This result verifies the active Duo simulator configuration only. No backend changes.
