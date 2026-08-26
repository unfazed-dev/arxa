// App Strings — showcase demo of the named-copy vocabulary
//
// Demonstrates the per-app strings file every scaffolded arxa app carries
// in lib/ui/common/. See kit/core/lib/common/arxa_kit_app_strings.dart for
// the convention. Rules demonstrated here:
// - `abxStr` prefix, const String, one name per piece of fixed copy.
// - Names are structural (feature + slot), not content-derived, so retyping
//   copy in arxa studio never forces a rename.
// - Runtime data (a note's title the user typed) is never named here.

// Notes — empty state
const String abxStrNotesEmptyTitle = 'No notes yet';
const String abxStrNotesEmptySubtitle = 'Create your first note to get started';

// Notes — create account form
const String abxStrNotesCreateAccountTitle = 'Create account';
const String abxStrNotesCreateAccountSubmit = 'Sign up';

// Startup — brand lockup (the all-caps wordmark IS the copy, not a style)
const String abxStrStartupAppTitle = 'ARXA SHOWCASE';

// Unknown route
const String abxStrUnknownRouteTitle = 'Page not found';
