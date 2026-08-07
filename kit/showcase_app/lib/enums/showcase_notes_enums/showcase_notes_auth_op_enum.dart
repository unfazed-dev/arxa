/// The auth ops shared by the sign-in and create-account viewmodels —
/// `.name` is the AppBoxKitAction hub key (the create-account VM reads
/// [signUp]'s state cross-VM by this key).
enum ShowcaseNotesAuthOp { signIn, signUp, requestOtp, confirmOtp, google, apple, anonymous }
