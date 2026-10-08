# Pablo Jhob — Personal Voice Assistant (Design)

Date: 2026-10-09 · Target device: iPhone 17e (iOS 26), sideloaded via Sideloadly
Base: Edge0Phone iOS app (`ios/`), Edge0 8B on-device model, offline.

## Goal
Turn the Edge0Phone chat app ("Pablo Jhob") into a Siri-like personal assistant that is
*different* from Siri: own personality and voice, remembers the user, real conversation,
fully offline/private, and able to act on the phone through approved iOS APIs.

## Non-goals
- Replacing Siri at the OS level, background wake word ("Hey Pablo"), reading other apps'
  screens/notifications, answering calls — not possible on stock iOS.
- Internet features (weather/news) — breaks the offline/egress posture.
- Share extension (second app target) — deferred.
- 35B model support for new features — 8B only.

## Hard constraints
1. **Prefill is slow on iPhone** (~7 tok/s published on short prompts). Every token injected
   before the user's text costs latency. Persona + memory context budget: **≤ 150 tokens**
   at start; Build 1 measures real TTFT on the 17e and adjusts. The context is sent only on the
   first turn of a chat (engine keeps KV state for later turns).
2. Model is 8B INT4: tool-use must be a **small fixed action vocabulary** with strict parsing.
3. Free Apple ID signing: no paid entitlements (no App Groups, no increased-memory-limit).
4. No Mac locally: everything builds on GitHub Actions (`.github/workflows/build-ios.yml`);
   pure logic is unit-tested on the macOS runner; device behaviour is tested by the user.
5. Bundle ID stays `com.siomai666.edge0phone` so Documents (model weights, memory DB) survive
   reinstalls.

## Architecture
New pure-Swift module **`PabloCore`** (SwiftPM target, no MLX/UIKit deps → testable on macOS):

| Unit | Responsibility | Interface |
|---|---|---|
| `Persona` | name, character preset, languages, voice id → system text | `Persona.systemPrompt(budget:) -> String` |
| `MemorySummary` | pick + compress profile/facts into ≤N tokens | `MemorySummary.build(profile:facts:budget:) -> String` |
| `ActionParser` | extract `<act>{json}</act>` from model output, validate against vocabulary | `ActionParser.parse(_ text:) -> (visibleText, [AssistantAction])` |
| `AssistantAction` | enum: reminder, calendarEvent, timer, alarm, openApp, draftMessage, toggle(setting), note | Codable, validated |
| `NoteToTasks` | prompt + parser turning a voice note into actions | uses ActionParser |
| `BriefingComposer` | template text from today's reminders/events/facts | pure function |

App-side (in `Edge0PhoneProbe/`, split out of the 568-line ContentView into focused files):

| File | Responsibility |
|---|---|
| `VoiceInput.swift` | SFSpeechRecognizer, `requiresOnDeviceRecognition = true`, push-to-talk + auto-stop on silence |
| `VoiceOutput.swift` | AVSpeechSynthesizer, speaks streamed reply sentence-by-sentence |
| `PabloIntents.swift` | App Intents: "Talk to Pablo" (opens app, starts listening) → Action Button / Siri / Control Center |
| `MemoryStore.swift` | SwiftData models: Profile, Fact, Conversation, Message; "forget X" |
| `ActionRunner.swift` | executes confirmed actions: EventKit (reminders/calendar), AlarmKit/notifications (timers/alarms), URL schemes (open app), MFMessageCompose/mail (draft), `shortcuts://run-shortcut` for toggles |
| `ProactiveScheduler.swift` | UNUserNotificationCenter daily briefing / recap / nudges |
| `LockGate.swift` | Face ID via LocalAuthentication |
| `SettingsView.swift`, `ActionCardView.swift`, `OrbView.swift` | UI |

Engine change (minimal): `Edge0ChatEngine.reply(..., systemPrompt: String?)` — inserted into the
existing `<role>SYSTEM</role>` block of `firstTurn` only. Default nil = today's behaviour.

## Data flow (one voice turn)
Action Button → `TalkToPabloIntent` opens app → VoiceInput transcribes → app builds
`systemPrompt = Persona + MemorySummary` (first turn only) → engine streams text →
ActionParser strips `<act>` blocks → VoiceOutput speaks visible text → each action shown as an
**ActionCard**; user taps Confirm → ActionRunner executes → result line appended to chat.
"Remember X" / "forget X" → handled as `note`/forget actions writing MemoryStore.

## Builds (each = one CI build + user device test)
1. **Voice + Siri button**: VoiceInput, VoiceOutput, TalkToPablo intent, persona/voice picker,
   Face ID lock, `systemPrompt` engine hook, TTFT measurement shown in UI.
2. **Memory**: SwiftData store, profile screen, notebook facts, saved chat list, forget/wipe.
3. **Actions**: ActionParser + vocabulary, ActionCard, EventKit/AlarmKit/open-app/draft,
   toggle shortcut (user installs a provided "Pablo Toggle" shortcut once), voice note → tasks.
4. **Proactive**: morning briefing, end-of-day recap, nudges, focus timer.
5. **Extras**: two-way translator mode, voice games, Image Playground (if Apple Intelligence
   available on device), PDF/photo Q&A (PDFKit + Vision OCR), daily fact/joke.

## Error handling
- Permission denied (mic/speech/reminders/calendar/notifications) → text fallback + message
  naming the setting to enable. Never crash.
- Malformed/unknown `<act>` → dropped silently, visible text kept; logged in debug panel.
- Actions never execute without an explicit Confirm tap; messages are never auto-sent.
- Speech recognizer unavailable offline for a language → tell user, offer typing.
- Memory DB corruption → move aside, start fresh, tell user.

## Testing
- `PabloCoreTests` (XCTest, macOS runner, run in CI before the device build): persona prompt
  budget, MemorySummary budget/priority, ActionParser (valid, malformed, unknown, multiple,
  injection inside user-quoted text), NoteToTasks parsing, BriefingComposer.
- Per-build device checklist for the user (e.g. "say: remind me at 3 pm to check S8051").
- CI gate: workflow fails if PabloCore tests fail.

## Risks
- TTFT with system prompt may be too slow → mitigation: shrink budget; prewarm the system
  prefix right after model load, before the user speaks.
- 8B may emit actions unreliably → few-shot examples kept tiny; confirm cards catch errors.
- AlarmKit / Image Playground availability on iOS 26 / 17e unverified → feature-detect at runtime.
