# Architecture retained

`@MainActor @Observable AppStore` remains the single source of shared session state. `KindredRepository` and `InMemoryKindredRepository` remain the mutation boundary. Screens read a fresh `SessionSnapshot`; forms commit drafts only on Save. Four `NavigationStack`s remain inside the native `TabView`. No storage or networking dependency was added.

Mutual-like creation stays in the repository and is idempotent per member. An existing conversation is reused with its messages intact. The store presents a celebration only on the transition from unmatched to matched. Presentation and the pending chat route are transient UI state. A match can be dismissed without creating or sending a message. Blocking removes likes, matches and chats and dismisses the blocked member's pending celebration.

`MainTabs` now owns an explicit selected tab and a Chats path solely to route **Say hello** into the existing chat. The floating tab bar, translucency, four destinations and Discovery scrolling layout are retained.

`ExperienceModels` adds computed calendar-day message groups, previews, optional story-section counts and draft suggestions from existing prompts. It creates no members, conversations, messages or personal attributes. Empty conversations sort by match date until their first message.

Prompt and photo likes include the recipient and the specific item ID. A like has either a prompt ID, a photo ID, or neither for general interest; the repository rejects mixed or unavailable targets. Shared bundled photo IDs are always scoped to the recipient. Duplicate saves produce no additional record or feedback, and multiple item likes share one match/conversation. SavedInterest resolves display context from the recipient’s current demo profile for Likes and the match celebration. Removing interest clears all outgoing item likes for that member while preserving an existing conversation. Photo selection is local to each gallery. Discovery gestures remain transient view state; only intentional committed gestures mutate the repository. Previous/next photo buttons and named accessibility actions remain available.

Public profile previews use `store.member("me")`, which applies city privacy without changing the private editable draft. The optional story checklist counts biography, interests and at least one prompt answer; it does not grade faith, lifestyle or compatibility.

Production motion reads the system Reduce Motion environment. Debug UI tests can select that same motion branch without changing device settings. This is not proof of physical-device motion, haptics or spoken VoiceOver behavior.
