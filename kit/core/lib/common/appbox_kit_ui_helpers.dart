import 'dart:math';

import 'package:flutter/material.dart';

const double _tinySize = 4.0;
const double _xSmallSize = 8.0;
const double _smallSize = 16.0;
const double _mediumSize = 24.0;
const double _largeSize = 48.0;
const double _massiveSize = 96.0;

const Widget appBoxKitHorizontalSpaceTiny = SizedBox(width: _tinySize);
const Widget appBoxKitHorizontalSpaceXSmall = SizedBox(width: _xSmallSize);
const Widget appBoxKitHorizontalSpaceSmall = SizedBox(width: _smallSize);
const Widget appBoxKitHorizontalSpaceMedium = SizedBox(width: _mediumSize);
const Widget appBoxKitHorizontalSpaceLarge = SizedBox(width: _largeSize);
const Widget appBoxKitHorizontalSpaceMassive = SizedBox(width: _massiveSize);

const Widget appBoxKitVerticalSpaceTiny = SizedBox(height: _tinySize);
const Widget appBoxKitVerticalSpaceXSmall = SizedBox(height: _xSmallSize);
const Widget appBoxKitVerticalSpaceSmall = SizedBox(height: _smallSize);
const Widget appBoxKitVerticalSpaceMedium = SizedBox(height: _mediumSize);
const Widget appBoxKitVerticalSpaceLarge = SizedBox(height: _largeSize);
const Widget appBoxKitVerticalSpaceMassive = SizedBox(height: _massiveSize);

Widget appBoxKitSpacedDivider = const Column(
  children: <Widget>[
    appBoxKitVerticalSpaceMedium,
    Divider(color: Colors.blueGrey, height: 5.0),
    appBoxKitVerticalSpaceMedium,
  ],
);

Widget appBoxKitVerticalSpace(double height) => SizedBox(height: height);

Widget appBoxKitHorizontalSpace(double width) => SizedBox(width: width);

double appBoxKitScreenWidth(BuildContext context) => MediaQuery.of(context).size.width;
double appBoxKitScreenHeight(BuildContext context) => MediaQuery.of(context).size.height;

double appBoxKitScreenHeightFraction(
  BuildContext context, {
  int dividedBy = 1,
  double offsetBy = 0,
  double max = 3000,
}) =>
    min((appBoxKitScreenHeight(context) - offsetBy) / dividedBy, max);

double appBoxKitScreenWidthFraction(
  BuildContext context, {
  int dividedBy = 1,
  double offsetBy = 0,
  double max = 3000,
}) =>
    min((appBoxKitScreenWidth(context) - offsetBy) / dividedBy, max);

double appBoxKitHalfScreenWidth(BuildContext context) =>
    appBoxKitScreenWidthFraction(context, dividedBy: 2);

double appBoxKitThirdScreenWidth(BuildContext context) =>
    appBoxKitScreenWidthFraction(context, dividedBy: 3);

double appBoxKitQuarterScreenWidth(BuildContext context) =>
    appBoxKitScreenWidthFraction(context, dividedBy: 4);

double appBoxKitGetResponsiveHorizontalSpaceMedium(BuildContext context) =>
    appBoxKitScreenWidthFraction(context, dividedBy: 10);
double appBoxKitGetResponsiveSmallFontSize(BuildContext context) =>
    appBoxKitGetResponsiveFontSize(context, fontSize: 14, max: 15);

double appBoxKitGetResponsiveMediumFontSize(BuildContext context) =>
    appBoxKitGetResponsiveFontSize(context, fontSize: 16, max: 17);

double appBoxKitGetResponsiveLargeFontSize(BuildContext context) =>
    appBoxKitGetResponsiveFontSize(context, fontSize: 21, max: 31);

double appBoxKitGetResponsiveExtraLargeFontSize(BuildContext context) =>
    appBoxKitGetResponsiveFontSize(context, fontSize: 25);

double appBoxKitGetResponsiveMassiveFontSize(BuildContext context) =>
    appBoxKitGetResponsiveFontSize(context, fontSize: 30);

double appBoxKitGetResponsiveFontSize(
  BuildContext context, {
  double? fontSize,
  double? max,
}) {
  max ??= 100;

  var responsiveSize = min(
    appBoxKitScreenWidthFraction(context, dividedBy: 10) * ((fontSize ?? 100) / 100),
    max,
  );

  return responsiveSize;
}
