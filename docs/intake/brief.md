# Demo app — design brief

> Emitted by arxa-intake from elicited answers.
> **Intake elicits; it does not generate** (architecture §22).
> Fields marked **[inferred]** were not stated by the client and MUST
> be confirmed before design consumes this brief.

## Product

Demo app

_provenance: client_

## Audience

Indie devs

_provenance: client_

## What the app must do

- list projects
- run a build

_provenance: client_

## Existing systems

_Not stated._
## Targets

- macos

_provenance: client_

## Locales

_Not stated._
## Brand

> **[inferred]** — not stated by the client; confirm or correct.

none stated

_provenance: inferred_

## Design direction

_Not stated._
## Content anchors

_Not stated._
## Constraints

_Not stated._
## Out of scope

_Not stated._
## Layout template

_Not stated._
## Surface inventory — the registry seed

| id | shell | comp | label | states | surface |
|---|---|---|---|---|---|
| `projects.home` | projects | ProjectsHome | Home | loading, empty [inferred] | _null_ |
| `projects.new` | projects | ProjectsNew | New | error [inferred] | _null_ |

Every `surface` is `null` — intake names what the client asked for; design binds a surface to each.
