// Debug Configuration

/// Enable verbose logging for development.
/// Set to false in production to reduce log clutter.
const bool axEnableVerboseLogging = false;

// Device constraints

/// The max width for desktop layouts
const double axDesktopMaxConstraintWidth = 1250;

/// The max height for desktop layouts
const double axDesktopMaxConstraintHeight = 750;

/// The max width for tablet layouts
const double axTabletMaxConstraintWidth = 768;

/// The max height for tablet layouts
const double axTabletMaxConstraintHeight = 1024;

/// The max width for mobile layouts
const double axMobileMaxConstraintWidth = 375;

/// The max height for mobile layouts
const double axMobileMaxConstraintHeight = 812;

/// Constants used across the UI components

// Border Radius
const double axDefaultBorderRadius = 8;

// Opacity
const double axDefaultHoverOpacity = 0.1;
const double axSubtleHoverOpacity = 0.05;

// Sizes
const double axDefaultMobileButtonHeight = 60;
const double axDefaultIconSize = 40;
const double axDefaultMobileTextFieldHeight = 68;
const double axDefaultMobileTextFieldVerticalPadding = axPad20;
const double axDefaultMobileTextFieldHorizontalPadding = axPad16;
const double axDefaultMobileTabHeight = 48;

const double axDefaultDesktopTextFieldHeight = 40;
const double axDefaultDesktopTabHeight = 40;
const double axDefaultDesktopButtonHeight = 40;

// AppBoxKitButton Size Constants
const double axButtonHeightTiny = 32.0;
const double axButtonHeightSmall = 40.0;
const double axButtonHeightMedium = 48.0;
const double axButtonHeightLarge = 56.0;
const double axButtonHeightXLarge = 64.0;
const double axButtonHeightXXLarge = 72.0;

const double axButtonPaddingTiny = 12.0;
const double axButtonPaddingSmall = 16.0;
const double axButtonPaddingMedium = 16.0;
const double axButtonPaddingLarge = 24.0;
const double axButtonPaddingXLarge = 28.0;
const double axButtonPaddingXXLarge = 32.0;

const double axButtonIconSizeTiny = 16.0;
const double axButtonIconSizeSmall = 18.0;
const double axButtonIconSizeMedium = 16.0;
const double axButtonIconSizeLarge = 24.0;
const double axButtonIconSizeXLarge = 28.0;
const double axButtonIconSizeXXLarge = 30.0;

// Note: Button text sizes use semantic font constants:
// tiny: axFont13, small: axFontSmall, medium: axFontMedium
// large: axFontLarge (DEFAULT), xlarge: axFontXLarge, xxlarge: axFont22

// AppBoxKitInput/TextField Size Constants
const double axTextFieldHeightTiny = 32.0;
const double axTextFieldHeightSmall = 40.0;
const double axTextFieldHeightMedium = 48.0;
const double axTextFieldHeightLarge = 56.0;
const double axTextFieldHeightXLarge = 64.0;
const double axTextFieldHeightXXLarge = 68.0; // Mobile default

const double axTextFieldPaddingTiny = 8.0;
const double axTextFieldPaddingSmall = 12.0;
const double axTextFieldPaddingMedium = 16.0;
const double axTextFieldPaddingLarge = 20.0;
const double axTextFieldPaddingXLarge = 24.0;
const double axTextFieldPaddingXXLarge = 28.0;

// AppBoxKitOtpInput Size Constants
const double axOtpSlotSize = 44.0;
const double axOtpSlotGap = 2.0;

// AppBoxKitCheckbox & AppBoxKitRadio Size Constants
const double axCheckboxDefaultSize = 100.0;
const double axCheckboxDefaultIconSize = 32.0;
const double axCheckboxDefaultBorderWidth = 1.0;
// Note: Border radius uses axDefaultBorderRadius = 8.0

// Padding
const double axDefaultHorizontalPadding = 16;
const double axDefaultVerticalPadding = 4;

// APPBAR
const double axAppBarHeight = 64;

// PADDINGS
const double axPad1 = 1;
const double axPad2 = 2;
const double axPad3 = 3;
const double axPad4 = 4;
const double axPad5 = 5;
const double axPad6 = 6;
const double axPad7 = 7;
const double axPad8 = 8;
const double axPad9 = 9;
const double axPad10 = 10;
const double axPad11 = 11;
const double axPad12 = 12;
const double axPad13 = 13;
const double axPad14 = 14;
const double axPad15 = 15;
const double axPad16 = 16;
const double axPad17 = 17;
const double axPad18 = 18;
const double axPad19 = 19;
const double axPad20 = 20;
const double axPad22 = 22;
const double axPad24 = 24;
const double axPad26 = 26;
const double axPad28 = 28;
const double axPad30 = 30;
const double axPad32 = 32;
const double axPad34 = 34;
const double axPad36 = 36;
const double axPad38 = 38;
const double axPad40 = 40;
const double axPad42 = 42;
const double axPad44 = 44;
const double axPad46 = 46;
const double axPad48 = 48;
const double axPad50 = 50;
const double axPad60 = 60;
const double axPad72 = 72;
const double axPad80 = 80;

// FONTS
const double axFont2 = 2;
const double axFont4 = 4;
const double axFont6 = 6;
const double axFont8 = 8;
const double axFont10 = 10;
const double axFont12 = 12;
const double axFont13 = 13;
const double axFont14 = 14;
const double axFont16 = 16;
const double axFont18 = 18;
const double axFont20 = 20;
const double axFont22 = 22;
const double axFont24 = 24;
const double axFont26 = 26;
const double axFont28 = 28;
const double axFont30 = 30;
const double axFont32 = 32;
const double axFont34 = 34;
const double axFont36 = 36;
const double axFont38 = 38;
const double axFont40 = 40;
const double axFont42 = 42;
const double axFont44 = 44;
const double axFont46 = 46;
const double axFont48 = 48;
const double axFont50 = 50;
const double axFont60 = 60;
const double axFont72 = 72;
const double axFont80 = 80;

// Semantic Font Sizes (for easier usage in TextStyle)
const double axFontTiny = axFont10; // 10 - Smallest text
const double axFontXSmall = axFont12; // 12 - Extra small (captions, hints)
const double axFontSmall = axFont14; // 14 - Small text
const double axFontMedium = axFont16; // 16 - Medium/body text (DEFAULT)
const double axFontLarge = axFont18; // 18 - Large text
const double axFontXLarge = axFont20; // 20 - Extra large
const double axFontXXLarge = axFont24; // 24 - Headings
const double axFontXXXLarge = axFont32; // 32 - Large headings
const double axFontHuge = axFont48; // 48 - Display text

// RADII
const double axRad0 = 0;
const double axRad2 = 2;
const double axRad4 = 4;
const double axRad6 = 6;
const double axRad8 = 8;
const double axRad10 = 10;
const double axRad12 = 12;
const double axRad14 = 14;
const double axRad16 = 16;
const double axRad18 = 18;
const double axRad20 = 20;
const double axRad22 = 22;
const double axRad24 = 24;
const double axRad26 = 26;
const double axRad28 = 28;
const double axRad30 = 30;
const double axRad32 = 32;
const double axRad34 = 34;
const double axRad36 = 36;

// SIZE
const double axSize1 = 1;
const double axSize2 = 2;
const double axSize3 = 3;
const double axSize4 = 4;
const double axSize5 = 5;
const double axSize6 = 6;
const double axSize7 = 7;
const double axSize8 = 8;
const double axSize9 = 9;
const double axSize10 = 10;
const double axSize12 = 12;
const double axSize14 = 14;
const double axSize16 = 16;
const double axSize18 = 18;
const double axSize20 = 20;
const double axSize22 = 22;
const double axSize24 = 24;
const double axSize26 = 26;
const double axSize28 = 28;
const double axSize30 = 30;
const double axSize32 = 32;
const double axSize34 = 34;
const double axSize36 = 36;
const double axSize38 = 38;
const double axSize40 = 40;
const double axSize42 = 42;
const double axSize44 = 44;
const double axSize46 = 46;
const double axSize48 = 48;
const double axSize50 = 50;
const double axSize60 = 60;
const double axSize72 = 72;
const double axSize80 = 80;
const double axSize320 = 320;
const double axSize360 = 360;
const double axSize400 = 400;
const double axSize450 = 450;
const double axSize500 = 500;

// Opacity

const double axOpacity100 = 1.0;
const double axOpacity95 = 0.95;
const double axOpacity90 = 0.9;
const double axOpacity85 = 0.85;
const double axOpacity80 = 0.8;
const double axOpacity75 = 0.75;
const double axOpacity70 = 0.7;
const double axOpacity65 = 0.65;
const double axOpacity60 = 0.6;
const double axOpacity55 = 0.55;
const double axOpacity50 = 0.5;
const double axOpacity45 = 0.45;
const double axOpacity40 = 0.4;
const double axOpacity35 = 0.35;
const double axOpacity30 = 0.3;
const double axOpacity25 = 0.25;
const double axOpacity20 = 0.2;
const double axOpacity15 = 0.15;
const double axOpacity10 = 0.1;
const double axOpacity095 = 0.095;
const double axOpacity090 = 0.09;
const double axOpacity085 = 0.085;
const double axOpacity080 = 0.08;
const double axOpacity075 = 0.075;
const double axOpacity070 = 0.07;
const double axOpacity065 = 0.065;
const double axOpacity060 = 0.06;
const double axOpacity055 = 0.055;
const double axOpacity050 = 0.05;
const double axOpacity045 = 0.045;
const double axOpacity040 = 0.04;
const double axOpacity035 = 0.035;
const double axOpacity030 = 0.03;
const double axOpacity025 = 0.025;
const double axOpacity020 = 0.02;
const double axOpacity015 = 0.015;
const double axOpacity010 = 0.01;
const double axOpacity0 = 0.0;

// Elevation
const double axElev100 = 100.0;
const double axElev98 = 98.0;
const double axElev96 = 96.0;
const double axElev94 = 94.0;
const double axElev92 = 92.0;
const double axElev90 = 90.0;
const double axElev88 = 88.0;
const double axElev86 = 86.0;
const double axElev84 = 84.0;
const double axElev82 = 82.0;
const double axElev80 = 80.0;
const double axElev78 = 78.0;
const double axElev76 = 76.0;
const double axElev74 = 74.0;
const double axElev72 = 72.0;
const double axElev70 = 70.0;
const double axElev68 = 68.0;
const double axElev66 = 66.0;
const double axElev64 = 64.0;
const double axElev62 = 62.0;
const double axElev60 = 60.0;
const double axElev58 = 58.0;
const double axElev56 = 56.0;
const double axElev54 = 54.0;
const double axElev52 = 52.0;
const double axElev50 = 50.0;
const double axElev48 = 48.0;
const double axElev46 = 46.0;
const double axElev44 = 44.0;
const double axElev42 = 42.0;
const double axElev40 = 40.0;
const double axElev38 = 38.0;
const double axElev36 = 36.0;
const double axElev34 = 34.0;
const double axElev32 = 32.0;
const double axElev30 = 30.0;
const double axElev28 = 28.0;
const double axElev26 = 26.0;
const double axElev24 = 24.0;
const double axElev22 = 22.0;
const double axElev20 = 20.0;
const double axElev18 = 18.0;
const double axElev16 = 16.0;
const double axElev14 = 14.0;
const double axElev12 = 12.0;
const double axElev10 = 10.0;

// Gap
const double axGap100 = 100.0;
const double axGap98 = 98.0;
const double axGap96 = 96.0;
const double axGap94 = 94.0;
const double axGap92 = 92.0;
const double axGap90 = 90.0;
const double axGap88 = 88.0;
const double axGap86 = 86.0;
const double axGap84 = 84.0;
const double axGap82 = 82.0;
const double axGap80 = 80.0;
const double axGap78 = 78.0;
const double axGap76 = 76.0;
const double axGap74 = 74.0;
const double axGap72 = 72.0;
const double axGap70 = 70.0;
const double axGap68 = 68.0;
const double axGap66 = 66.0;
const double axGap64 = 64.0;
const double axGap62 = 62.0;
const double axGap60 = 60.0;
const double axGap58 = 58.0;
const double axGap56 = 56.0;
const double axGap54 = 54.0;
const double axGap52 = 52.0;
const double axGap50 = 50.0;
const double axGap48 = 48.0;
const double axGap46 = 46.0;
const double axGap44 = 44.0;
const double axGap42 = 42.0;
const double axGap40 = 40.0;
const double axGap38 = 38.0;
const double axGap36 = 36.0;
const double axGap34 = 34.0;
const double axGap32 = 32.0;
const double axGap30 = 30.0;
const double axGap28 = 28.0;
const double axGap26 = 26.0;
const double axGap24 = 24.0;
const double axGap22 = 22.0;
const double axGap20 = 20.0;
const double axGap18 = 18.0;
const double axGap16 = 16.0;
const double axGap14 = 14.0;
const double axGap12 = 12.0;
const double axGap10 = 10.0;
const double axGap8 = 8.0;
const double axGap6 = 6.0;
const double axGap4 = 4.0;
const double axGap2 = 2.0;
const double axGap0 = 0.0;

// Sigma
const double axSigma100 = 100.0;
const double axSigma98 = 98.0;
const double axSigma96 = 96.0;
const double axSigma94 = 94.0;
const double axSigma92 = 92.0;
const double axSigma90 = 90.0;
const double axSigma88 = 88.0;
const double axSigma86 = 86.0;
const double axSigma84 = 84.0;
const double axSigma82 = 82.0;
const double axSigma80 = 80.0;
const double axSigma78 = 78.0;
const double axSigma76 = 76.0;
const double axSigma74 = 74.0;
const double axSigma72 = 72.0;
const double axSigma70 = 70.0;
const double axSigma68 = 68.0;
const double axSigma66 = 66.0;
const double axSigma64 = 64.0;
const double axSigma62 = 62.0;
const double axSigma60 = 60.0;
const double axSigma58 = 58.0;
const double axSigma56 = 56.0;
const double axSigma54 = 54.0;
const double axSigma52 = 52.0;
const double axSigma50 = 50.0;
const double axSigma48 = 48.0;
const double axSigma46 = 46.0;
const double axSigma44 = 44.0;
const double axSigma42 = 42.0;
const double axSigma40 = 40.0;
const double axSigma38 = 38.0;
const double axSigma36 = 36.0;
const double axSigma34 = 34.0;
const double axSigma32 = 32.0;
const double axSigma30 = 30.0;
const double axSigma28 = 28.0;
const double axSigma26 = 26.0;
const double axSigma24 = 24.0;
const double axSigma22 = 22.0;
const double axSigma20 = 20.0;
const double axSigma18 = 18.0;
const double axSigma16 = 16.0;
const double axSigma14 = 14.0;
const double axSigma12 = 12.0;
const double axSigma10 = 10.0;
const double axSigma8 = 8.0;
const double axSigma6 = 6.0;
const double axSigma4 = 4.0;
const double axSigma2 = 2.0;
const double axSigma0 = 0.0;

// Offset
const double axOffset100 = 100.0;
const double axOffset98 = 98.0;
const double axOffset96 = 96.0;
const double axOffset94 = 94.0;
const double axOffset92 = 92.0;
const double axOffset90 = 90.0;
const double axOffset88 = 88.0;
const double axOffset86 = 86.0;
const double axOffset84 = 84.0;
const double axOffset82 = 82.0;
const double axOffset80 = 80.0;
const double axOffset78 = 78.0;
const double axOffset76 = 76.0;
const double axOffset74 = 74.0;
const double axOffset72 = 72.0;
const double axOffset70 = 70.0;
const double axOffset68 = 68.0;
const double axOffset66 = 66.0;
const double axOffset64 = 64.0;
const double axOffset62 = 62.0;
const double axOffset60 = 60.0;
const double axOffset58 = 58.0;
const double axOffset56 = 56.0;
const double axOffset54 = 54.0;
const double axOffset52 = 52.0;
const double axOffset50 = 50.0;
const double axOffset48 = 48.0;
const double axOffset46 = 46.0;
const double axOffset44 = 44.0;
const double axOffset42 = 42.0;
const double axOffset40 = 40.0;
const double axOffset38 = 38.0;
const double axOffset36 = 36.0;
const double axOffset34 = 34.0;
const double axOffset32 = 32.0;
const double axOffset30 = 30.0;
const double axOffset28 = 28.0;
const double axOffset26 = 26.0;
const double axOffset24 = 24.0;
const double axOffset22 = 22.0;
const double axOffset20 = 20.0;
const double axOffset18 = 18.0;
const double axOffset16 = 16.0;
const double axOffset14 = 14.0;
const double axOffset12 = 12.0;
const double axOffset10 = 10.0;
const double axOffset8 = 8.0;
const double axOffset6 = 6.0;
const double axOffset4 = 4.0;
const double axOffset2 = 2.0;
const double axOffset0 = 0.0;

// Percentage
const double axPercent100 = 1.0;
const double axPercent95 = 0.95;
const double axPercent90 = 0.9;
const double axPercent85 = 0.85;
const double axPercent80 = 0.8;
const double axPercent75 = 0.75;
const double axPercent70 = 0.7;
const double axPercent65 = 0.65;
const double axPercent60 = 0.6;
const double axPercent55 = 0.55;
const double axPercent50 = 0.5;
const double axPercent45 = 0.45;
const double axPercent40 = 0.4;
const double axPercent35 = 0.35;
const double axPercent30 = 0.3;
const double axPercent25 = 0.25;
const double axPercent20 = 0.2;
const double axPercent15 = 0.15;
const double axPercent10 = 0.1;
