// App Strings — named copy vocabulary (generic kit template)
//
// CONVENTION (one-vocabulary rule, ratified in the Q-grill):
// - Every user-facing fixed string (copy) in an arxa app is declared here
//   as an `abxStr`-prefixed const — `abx` matches
//   arxa_kit_app_constants.dart style, `Str` marks it as string copy.
// - The design refers to the NAME, never to loose words. design.json stores
//   the name; the scaffolder emits the same name as a Dart const; arxa
//   studio's inspector edits copy by rewriting the value behind the name —
//   written once, re-rendered everywhere the name appears.
// - Runtime data (anything a user typed or a service returned) is NEVER
//   named here. The inspector tags it as data and refuses copy edits on it.
// - Each app owns its own arxa_kit_app_strings.dart (scaffolded into
//   lib/ui/common/ alongside the kit common copy). This kit file carries
//   only strings generic to every arxa app.

// Generic actions
const String abxStrActionOk = 'OK';
const String abxStrActionCancel = 'Cancel';
const String abxStrActionSave = 'Save';
const String abxStrActionDelete = 'Delete';
const String abxStrActionRetry = 'Retry';
const String abxStrActionClose = 'Close';
const String abxStrActionBack = 'Back';

// Generic states
const String abxStrStateLoading = 'Loading…';
const String abxStrStateEmpty = 'Nothing here yet';
const String abxStrStateErrorGeneric = 'Something went wrong';
const String abxStrStateOffline = 'You are offline';
