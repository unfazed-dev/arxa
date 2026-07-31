# Self-Test App — design brief

Elicited via appbox-story-mapper; the full story map lives alongside
this brief (`story-map.json`, `story_map.html`). Priorities are MoSCoW,
grouped into release swimlanes. Every registry surface must trace to
the surface inventory table below (gates/intake, plan 10.7).

## Product

Self-Test App

## Releases

- **Release 1**
- **Release 2** — hardening pass

## The things the app must do

### User System

#### Registration & Login

- [must/Release 1] Phone signup — SMS-verified onboarding
- [should/Release 2] Email login

#### 注册

- [must/Release 1] Phone signup

#### Legacy SSO

- [wont/Release 2] SAML login

### User System

#### Registration & Login


## Surface inventory

| id | label | priority | release |
|----|-------|----------|---------|
| `user.registration` | Registration & Login | must | Release 1 |
| `user.s` | 注册 | must | Release 1 |
| `user2.registration2` | Registration & Login |  |  |

## Out of scope

- Legacy SSO (User System) — all stories Won't-have this cycle
