// Debug Configuration

/// Enable verbose logging for development.
/// Set to false in production to reduce log clutter.
const bool kEnableVerboseLogging = false;

// Device constraints

/// The max width for desktop layouts
const double kdDesktopMaxConstraintWidth = 1250;

/// The max height for desktop layouts
const double kdDesktopMaxConstraintHeight = 750;

/// The max width for tablet layouts
const double kdTabletMaxConstraintWidth = 768;

/// The max height for tablet layouts
const double kdTabletMaxConstraintHeight = 1024;

/// The max width for mobile layouts
const double kdMobileMaxConstraintWidth = 375;

/// The max height for mobile layouts
const double kdMobileMaxConstraintHeight = 812;

/// Constants used across the UI components

// Border Radius
const double kDefaultBorderRadius = 8;

// Opacity
const double kDefaultHoverOpacity = 0.1;
const double kSubtleHoverOpacity = 0.05;

// Sizes
const double kDefaultMobileButtonHeight = 60;
const double kDefaultIconSize = 40;
const double kDefaultMobileTextFieldHeight = 68;
const double kDefaultMobileTextFieldVerticalPadding = kPad20;
const double kDefaultMobileTextFieldHorizontalPadding = kPad16;
const double kDefaultMobileTabHeight = 48;

const double kDefaultDesktopTextFieldHeight = 40;
const double kDefaultDesktopTabHeight = 40;
const double kDefaultDesktopButtonHeight = 40;

// KitButton Size Constants
const double kButtonHeightTiny = 32.0;
const double kButtonHeightSmall = 40.0;
const double kButtonHeightMedium = 48.0;
const double kButtonHeightLarge = 56.0;
const double kButtonHeightXLarge = 64.0;
const double kButtonHeightXXLarge = 72.0;

const double kButtonPaddingTiny = 12.0;
const double kButtonPaddingSmall = 16.0;
const double kButtonPaddingMedium = 16.0;
const double kButtonPaddingLarge = 24.0;
const double kButtonPaddingXLarge = 28.0;
const double kButtonPaddingXXLarge = 32.0;

const double kButtonIconSizeTiny = 16.0;
const double kButtonIconSizeSmall = 18.0;
const double kButtonIconSizeMedium = 16.0;
const double kButtonIconSizeLarge = 24.0;
const double kButtonIconSizeXLarge = 28.0;
const double kButtonIconSizeXXLarge = 30.0;

// Note: Button text sizes use semantic font constants:
// tiny: kFont13, small: kFontSmall, medium: kFontMedium
// large: kFontLarge (DEFAULT), xlarge: kFontXLarge, xxlarge: kFont22

// KitInput/TextField Size Constants
const double kTextFieldHeightTiny = 32.0;
const double kTextFieldHeightSmall = 40.0;
const double kTextFieldHeightMedium = 48.0;
const double kTextFieldHeightLarge = 56.0;
const double kTextFieldHeightXLarge = 64.0;
const double kTextFieldHeightXXLarge = 68.0; // Mobile default

const double kTextFieldPaddingTiny = 8.0;
const double kTextFieldPaddingSmall = 12.0;
const double kTextFieldPaddingMedium = 16.0;
const double kTextFieldPaddingLarge = 20.0;
const double kTextFieldPaddingXLarge = 24.0;
const double kTextFieldPaddingXXLarge = 28.0;

// KitOtpInput Size Constants
const double kOtpSlotSize = 44.0;
const double kOtpSlotGap = 2.0;

// KitCheckbox & KitRadio Size Constants
const double kCheckboxDefaultSize = 100.0;
const double kCheckboxDefaultIconSize = 32.0;
const double kCheckboxDefaultBorderWidth = 1.0;
// Note: Border radius uses kDefaultBorderRadius = 8.0

// Padding
const double kDefaultHorizontalPadding = 16;
const double kDefaultVerticalPadding = 4;

// APPBAR
const double kAppBarHeight = 64;

// PADDINGS
const double kPad1 = 1;
const double kPad2 = 2;
const double kPad3 = 3;
const double kPad4 = 4;
const double kPad5 = 5;
const double kPad6 = 6;
const double kPad7 = 7;
const double kPad8 = 8;
const double kPad9 = 9;
const double kPad10 = 10;
const double kPad11 = 11;
const double kPad12 = 12;
const double kPad13 = 13;
const double kPad14 = 14;
const double kPad15 = 15;
const double kPad16 = 16;
const double kPad17 = 17;
const double kPad18 = 18;
const double kPad19 = 19;
const double kPad20 = 20;
const double kPad22 = 22;
const double kPad24 = 24;
const double kPad26 = 26;
const double kPad28 = 28;
const double kPad30 = 30;
const double kPad32 = 32;
const double kPad34 = 34;
const double kPad36 = 36;
const double kPad38 = 38;
const double kPad40 = 40;
const double kPad42 = 42;
const double kPad44 = 44;
const double kPad46 = 46;
const double kPad48 = 48;
const double kPad50 = 50;
const double kPad60 = 60;
const double kPad72 = 72;
const double kPad80 = 80;

// FONTS
const double kFont2 = 2;
const double kFont4 = 4;
const double kFont6 = 6;
const double kFont8 = 8;
const double kFont10 = 10;
const double kFont12 = 12;
const double kFont13 = 13;
const double kFont14 = 14;
const double kFont16 = 16;
const double kFont18 = 18;
const double kFont20 = 20;
const double kFont22 = 22;
const double kFont24 = 24;
const double kFont26 = 26;
const double kFont28 = 28;
const double kFont30 = 30;
const double kFont32 = 32;
const double kFont34 = 34;
const double kFont36 = 36;
const double kFont38 = 38;
const double kFont40 = 40;
const double kFont42 = 42;
const double kFont44 = 44;
const double kFont46 = 46;
const double kFont48 = 48;
const double kFont50 = 50;
const double kFont60 = 60;
const double kFont72 = 72;
const double kFont80 = 80;

// Semantic Font Sizes (for easier usage in TextStyle)
const double kFontTiny = kFont10; // 10 - Smallest text
const double kFontXSmall = kFont12; // 12 - Extra small (captions, hints)
const double kFontSmall = kFont14; // 14 - Small text
const double kFontMedium = kFont16; // 16 - Medium/body text (DEFAULT)
const double kFontLarge = kFont18; // 18 - Large text
const double kFontXLarge = kFont20; // 20 - Extra large
const double kFontXXLarge = kFont24; // 24 - Headings
const double kFontXXXLarge = kFont32; // 32 - Large headings
const double kFontHuge = kFont48; // 48 - Display text

// RADII
const double kRad0 = 0;
const double kRad2 = 2;
const double kRad4 = 4;
const double kRad6 = 6;
const double kRad8 = 8;
const double kRad10 = 10;
const double kRad12 = 12;
const double kRad14 = 14;
const double kRad16 = 16;
const double kRad18 = 18;
const double kRad20 = 20;
const double kRad22 = 22;
const double kRad24 = 24;
const double kRad26 = 26;
const double kRad28 = 28;
const double kRad30 = 30;
const double kRad32 = 32;
const double kRad34 = 34;
const double kRad36 = 36;

// SIZE
const double kSize1 = 1;
const double kSize2 = 2;
const double kSize3 = 3;
const double kSize4 = 4;
const double kSize5 = 5;
const double kSize6 = 6;
const double kSize7 = 7;
const double kSize8 = 8;
const double kSize9 = 9;
const double kSize10 = 10;
const double kSize12 = 12;
const double kSize14 = 14;
const double kSize16 = 16;
const double kSize18 = 18;
const double kSize20 = 20;
const double kSize22 = 22;
const double kSize24 = 24;
const double kSize26 = 26;
const double kSize28 = 28;
const double kSize30 = 30;
const double kSize32 = 32;
const double kSize34 = 34;
const double kSize36 = 36;
const double kSize38 = 38;
const double kSize40 = 40;
const double kSize42 = 42;
const double kSize44 = 44;
const double kSize46 = 46;
const double kSize48 = 48;
const double kSize50 = 50;
const double kSize60 = 60;
const double kSize72 = 72;
const double kSize80 = 80;
const double kSize320 = 320;
const double kSize360 = 360;
const double kSize400 = 400;
const double kSize450 = 450;
const double kSize500 = 500;

// Opacity

const double kOpacity100 = 1.0;
const double kOpacity95 = 0.95;
const double kOpacity90 = 0.9;
const double kOpacity85 = 0.85;
const double kOpacity80 = 0.8;
const double kOpacity75 = 0.75;
const double kOpacity70 = 0.7;
const double kOpacity65 = 0.65;
const double kOpacity60 = 0.6;
const double kOpacity55 = 0.55;
const double kOpacity50 = 0.5;
const double kOpacity45 = 0.45;
const double kOpacity40 = 0.4;
const double kOpacity35 = 0.35;
const double kOpacity30 = 0.3;
const double kOpacity25 = 0.25;
const double kOpacity20 = 0.2;
const double kOpacity15 = 0.15;
const double kOpacity10 = 0.1;
const double kOpacity095 = 0.095;
const double kOpacity090 = 0.09;
const double kOpacity085 = 0.085;
const double kOpacity080 = 0.08;
const double kOpacity075 = 0.075;
const double kOpacity070 = 0.07;
const double kOpacity065 = 0.065;
const double kOpacity060 = 0.06;
const double kOpacity055 = 0.055;
const double kOpacity050 = 0.05;
const double kOpacity045 = 0.045;
const double kOpacity040 = 0.04;
const double kOpacity035 = 0.035;
const double kOpacity030 = 0.03;
const double kOpacity025 = 0.025;
const double kOpacity020 = 0.02;
const double kOpacity015 = 0.015;
const double kOpacity010 = 0.01;
const double kOpacity0 = 0.0;

// Elevation
const double kElev100 = 100.0;
const double kElev98 = 98.0;
const double kElev96 = 96.0;
const double kElev94 = 94.0;
const double kElev92 = 92.0;
const double kElev90 = 90.0;
const double kElev88 = 88.0;
const double kElev86 = 86.0;
const double kElev84 = 84.0;
const double kElev82 = 82.0;
const double kElev80 = 80.0;
const double kElev78 = 78.0;
const double kElev76 = 76.0;
const double kElev74 = 74.0;
const double kElev72 = 72.0;
const double kElev70 = 70.0;
const double kElev68 = 68.0;
const double kElev66 = 66.0;
const double kElev64 = 64.0;
const double kElev62 = 62.0;
const double kElev60 = 60.0;
const double kElev58 = 58.0;
const double kElev56 = 56.0;
const double kElev54 = 54.0;
const double kElev52 = 52.0;
const double kElev50 = 50.0;
const double kElev48 = 48.0;
const double kElev46 = 46.0;
const double kElev44 = 44.0;
const double kElev42 = 42.0;
const double kElev40 = 40.0;
const double kElev38 = 38.0;
const double kElev36 = 36.0;
const double kElev34 = 34.0;
const double kElev32 = 32.0;
const double kElev30 = 30.0;
const double kElev28 = 28.0;
const double kElev26 = 26.0;
const double kElev24 = 24.0;
const double kElev22 = 22.0;
const double kElev20 = 20.0;
const double kElev18 = 18.0;
const double kElev16 = 16.0;
const double kElev14 = 14.0;
const double kElev12 = 12.0;
const double kElev10 = 10.0;

// Gap
const double kGap100 = 100.0;
const double kGap98 = 98.0;
const double kGap96 = 96.0;
const double kGap94 = 94.0;
const double kGap92 = 92.0;
const double kGap90 = 90.0;
const double kGap88 = 88.0;
const double kGap86 = 86.0;
const double kGap84 = 84.0;
const double kGap82 = 82.0;
const double kGap80 = 80.0;
const double kGap78 = 78.0;
const double kGap76 = 76.0;
const double kGap74 = 74.0;
const double kGap72 = 72.0;
const double kGap70 = 70.0;
const double kGap68 = 68.0;
const double kGap66 = 66.0;
const double kGap64 = 64.0;
const double kGap62 = 62.0;
const double kGap60 = 60.0;
const double kGap58 = 58.0;
const double kGap56 = 56.0;
const double kGap54 = 54.0;
const double kGap52 = 52.0;
const double kGap50 = 50.0;
const double kGap48 = 48.0;
const double kGap46 = 46.0;
const double kGap44 = 44.0;
const double kGap42 = 42.0;
const double kGap40 = 40.0;
const double kGap38 = 38.0;
const double kGap36 = 36.0;
const double kGap34 = 34.0;
const double kGap32 = 32.0;
const double kGap30 = 30.0;
const double kGap28 = 28.0;
const double kGap26 = 26.0;
const double kGap24 = 24.0;
const double kGap22 = 22.0;
const double kGap20 = 20.0;
const double kGap18 = 18.0;
const double kGap16 = 16.0;
const double kGap14 = 14.0;
const double kGap12 = 12.0;
const double kGap10 = 10.0;
const double kGap8 = 8.0;
const double kGap6 = 6.0;
const double kGap4 = 4.0;
const double kGap2 = 2.0;
const double kGap0 = 0.0;

// Sigma
const double kSigma100 = 100.0;
const double kSigma98 = 98.0;
const double kSigma96 = 96.0;
const double kSigma94 = 94.0;
const double kSigma92 = 92.0;
const double kSigma90 = 90.0;
const double kSigma88 = 88.0;
const double kSigma86 = 86.0;
const double kSigma84 = 84.0;
const double kSigma82 = 82.0;
const double kSigma80 = 80.0;
const double kSigma78 = 78.0;
const double kSigma76 = 76.0;
const double kSigma74 = 74.0;
const double kSigma72 = 72.0;
const double kSigma70 = 70.0;
const double kSigma68 = 68.0;
const double kSigma66 = 66.0;
const double kSigma64 = 64.0;
const double kSigma62 = 62.0;
const double kSigma60 = 60.0;
const double kSigma58 = 58.0;
const double kSigma56 = 56.0;
const double kSigma54 = 54.0;
const double kSigma52 = 52.0;
const double kSigma50 = 50.0;
const double kSigma48 = 48.0;
const double kSigma46 = 46.0;
const double kSigma44 = 44.0;
const double kSigma42 = 42.0;
const double kSigma40 = 40.0;
const double kSigma38 = 38.0;
const double kSigma36 = 36.0;
const double kSigma34 = 34.0;
const double kSigma32 = 32.0;
const double kSigma30 = 30.0;
const double kSigma28 = 28.0;
const double kSigma26 = 26.0;
const double kSigma24 = 24.0;
const double kSigma22 = 22.0;
const double kSigma20 = 20.0;
const double kSigma18 = 18.0;
const double kSigma16 = 16.0;
const double kSigma14 = 14.0;
const double kSigma12 = 12.0;
const double kSigma10 = 10.0;
const double kSigma8 = 8.0;
const double kSigma6 = 6.0;
const double kSigma4 = 4.0;
const double kSigma2 = 2.0;
const double kSigma0 = 0.0;

// Offset
const double kOffset100 = 100.0;
const double kOffset98 = 98.0;
const double kOffset96 = 96.0;
const double kOffset94 = 94.0;
const double kOffset92 = 92.0;
const double kOffset90 = 90.0;
const double kOffset88 = 88.0;
const double kOffset86 = 86.0;
const double kOffset84 = 84.0;
const double kOffset82 = 82.0;
const double kOffset80 = 80.0;
const double kOffset78 = 78.0;
const double kOffset76 = 76.0;
const double kOffset74 = 74.0;
const double kOffset72 = 72.0;
const double kOffset70 = 70.0;
const double kOffset68 = 68.0;
const double kOffset66 = 66.0;
const double kOffset64 = 64.0;
const double kOffset62 = 62.0;
const double kOffset60 = 60.0;
const double kOffset58 = 58.0;
const double kOffset56 = 56.0;
const double kOffset54 = 54.0;
const double kOffset52 = 52.0;
const double kOffset50 = 50.0;
const double kOffset48 = 48.0;
const double kOffset46 = 46.0;
const double kOffset44 = 44.0;
const double kOffset42 = 42.0;
const double kOffset40 = 40.0;
const double kOffset38 = 38.0;
const double kOffset36 = 36.0;
const double kOffset34 = 34.0;
const double kOffset32 = 32.0;
const double kOffset30 = 30.0;
const double kOffset28 = 28.0;
const double kOffset26 = 26.0;
const double kOffset24 = 24.0;
const double kOffset22 = 22.0;
const double kOffset20 = 20.0;
const double kOffset18 = 18.0;
const double kOffset16 = 16.0;
const double kOffset14 = 14.0;
const double kOffset12 = 12.0;
const double kOffset10 = 10.0;
const double kOffset8 = 8.0;
const double kOffset6 = 6.0;
const double kOffset4 = 4.0;
const double kOffset2 = 2.0;
const double kOffset0 = 0.0;

// Percentage
const double kPercent100 = 1.0;
const double kPercent95 = 0.95;
const double kPercent90 = 0.9;
const double kPercent85 = 0.85;
const double kPercent80 = 0.8;
const double kPercent75 = 0.75;
const double kPercent70 = 0.7;
const double kPercent65 = 0.65;
const double kPercent60 = 0.6;
const double kPercent55 = 0.55;
const double kPercent50 = 0.5;
const double kPercent45 = 0.45;
const double kPercent40 = 0.4;
const double kPercent35 = 0.35;
const double kPercent30 = 0.3;
const double kPercent25 = 0.25;
const double kPercent20 = 0.2;
const double kPercent15 = 0.15;
const double kPercent10 = 0.1;
