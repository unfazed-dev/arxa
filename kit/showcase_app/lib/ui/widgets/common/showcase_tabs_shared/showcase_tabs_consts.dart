/// Height the floating [AppBoxKitNativeTabBar] occupies above the system safe area
/// (M3E "small" bar = 64dp; the iOS Liquid Glass pill measures ~61pt plus its
/// float margin). The host shell's `extendBody` lets tab content slide under
/// the bar, so scrollable tab bodies add `MediaQuery.paddingOf(context)
/// .bottom + kShowcaseTabBarBlockHeight` of trailing clearance — without it
/// the last row lays out unreachable beneath the bar.
const double kShowcaseTabBarBlockHeight = 64.0;
