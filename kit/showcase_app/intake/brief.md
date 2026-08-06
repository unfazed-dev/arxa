# showcase_app — the appbox kit showcase: a real notes product (auth, notes CRUD, folders, search, media attachments) plus shell demos for every kit surface family — design brief

> Emitted by appbox-intake from elicited answers.
> **Intake elicits; it does not generate** (architecture §22).
> Fields marked **[inferred]** were not stated by the client and MUST
> be confirmed before design consumes this brief.

## Product

showcase_app — the appbox kit showcase: a real notes product (auth, notes CRUD, folders, search, media attachments) plus shell demos for every kit surface family

_provenance: founder_

## Audience

When I evaluate the appbox kit, I want a working notes app and live shell demos in one target, so I can judge the kit on real product behavior rather than static mockups

_provenance: founder_

## What the app must do

- sign in and create an account via email OTP, Google, Apple, or anonymously
- create, edit, pin, trash and restore notes
- organize notes into folders
- search notes by text
- attach photos and audio recordings to notes
- demonstrate the startup, unknown-route, home, application and profile shells

_provenance: founder_

## Existing systems

kit auth ports (email OTP, Google, Apple, anonymous); kit media ports for photo and audio capture

_provenance: founder_

## Targets

- ios
- android
- macos

_provenance: founder_

## Locales

- en

_provenance: founder_

## Brand

appbox kit showcase; neutral demo branding that defers to the kit theme

_provenance: founder_

## Design direction

- adjectives: honest, working, adaptive
- avoids: lorem ipsum, dead buttons, mock data presented as real

_provenance: founder_

## Content anchors

- Inbox — 3 pinned notes, 12 total
- Folder: Ideas — 5 notes
- Note with photo attachment and 0:42 audio memo
- Trash — 2 notes, restore or delete forever

_provenance: founder_

## Constraints

- the notes slice is a real product — no stubbed behavior
- everything is built from kit primitives and ports, no bespoke native code

_provenance: founder_

## Out of scope

- note sharing and collaboration
- rich-text editing
- sync across devices

_provenance: founder_

## Layout template

_Not stated._
## Surface inventory — the registry seed

| id | shell | comp | label | states | surface |
|---|---|---|---|---|---|
| `showcase.startup` | showcase | ShowcaseStartup | Startup | loading, error | _null_ |
| `showcase.unknown` | showcase | ShowcaseUnknown | Unknown route |  | _null_ |
| `showcase.notesauth` | showcase | ShowcaseNotesauth | Notes sign-in |  | _null_ |
| `showcase.createaccount` | showcase | ShowcaseCreateaccount | Create account |  | _null_ |
| `showcase.notes` | showcase | ShowcaseNotes | Notes inbox | loading, empty, error | _null_ |
| `showcase.noteeditor` | showcase | ShowcaseNoteeditor | Note editor | error [inferred] | _null_ |
| `showcase.notesfolder` | showcase | ShowcaseNotesfolder | Folder | empty | _null_ |
| `showcase.search` | showcase | ShowcaseSearch | Search | empty | _null_ |
| `showcase.home` | showcase | ShowcaseHome | Home shell | loading, empty [inferred] | _null_ |
| `showcase.application` | showcase | ShowcaseApplication | Application shell |  | _null_ |
| `showcase.profile` | showcase | ShowcaseProfile | Profile | error [inferred] | _null_ |
| `showcase.maps` | showcase | ShowcaseMaps | Maps demo |  | _null_ |
| `showcase.motion` | showcase | ShowcaseMotion | Motion demo |  | _null_ |
| `showcase.components` | showcase | ShowcaseComponents | Components gallery |  | _null_ |

Every `surface` is `null` — intake names what the client asked for; design binds a surface to each.

## Transition feedback — the other axis

A toast is a consequence of a TRANSITION, not a way a screen can look, so
it lives on the flow edge and never in `states`.

| flow | edge | kind | text |
|---|---|---|---|
| `flow-onboarding` | `showcase.notesauth` → `showcase.notes` | success | Signed in |
| `flow-create-account` | `showcase.notesauth` → `showcase.createaccount` | success | Create account [inferred] |
| `flow-create-account` | `showcase.createaccount` → `showcase.notes` | success | Account created |
| `flow-note-editing` | `showcase.noteeditor` → `showcase.notes` | success | Note saved |
