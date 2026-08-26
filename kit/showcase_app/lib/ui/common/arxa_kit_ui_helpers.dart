import 'dart:math';

import 'package:flutter/material.dart';

const double _tinySize = 4.0;
const double _xSmallSize = 8.0;
const double _smallSize = 16.0;
const double _mediumSize = 24.0;
const double _largeSize = 48.0;
const double _massiveSize = 96.0;

const Widget arxaKitHorizontalSpaceTiny = SizedBox(width: _tinySize);
const Widget arxaKitHorizontalSpaceXSmall = SizedBox(width: _xSmallSize);
const Widget arxaKitHorizontalSpaceSmall = SizedBox(width: _smallSize);
const Widget arxaKitHorizontalSpaceMedium = SizedBox(width: _mediumSize);
const Widget arxaKitHorizontalSpaceLarge = SizedBox(width: _largeSize);
const Widget arxaKitHorizontalSpaceMassive = SizedBox(width: _massiveSize);

const Widget arxaKitVerticalSpaceTiny = SizedBox(height: _tinySize);
const Widget arxaKitVerticalSpaceXSmall = SizedBox(height: _xSmallSize);
const Widget arxaKitVerticalSpaceSmall = SizedBox(height: _smallSize);
const Widget arxaKitVerticalSpaceMedium = SizedBox(height: _mediumSize);
const Widget arxaKitVerticalSpaceLarge = SizedBox(height: _largeSize);
const Widget arxaKitVerticalSpaceMassive = SizedBox(height: _massiveSize);

Widget arxaKitSpacedDivider = const Column(
  children: <Widget>[
    arxaKitVerticalSpaceMedium,
    Divider(color: Colors.blueGrey, height: 5.0),
    arxaKitVerticalSpaceMedium,
  ],
);

Widget arxaKitVerticalSpace(double height) => SizedBox(height: height);

Widget arxaKitHorizontalSpace(double width) => SizedBox(width: width);

double arxaKitScreenWidth(BuildContext context) =>
    MediaQuery.of(context).size.width;
double arxaKitScreenHeight(BuildContext context) =>
    MediaQuery.of(context).size.height;

double arxaKitScreenHeightFraction(
  BuildContext context, {
  int dividedBy = 1,
  double offsetBy = 0,
  double max = 3000,
}) =>
    min((arxaKitScreenHeight(context) - offsetBy) / dividedBy, max);

double arxaKitScreenWidthFraction(
  BuildContext context, {
  int dividedBy = 1,
  double offsetBy = 0,
  double max = 3000,
}) =>
    min((arxaKitScreenWidth(context) - offsetBy) / dividedBy, max);

double arxaKitHalfScreenWidth(BuildContext context) =>
    arxaKitScreenWidthFraction(context, dividedBy: 2);

double arxaKitThirdScreenWidth(BuildContext context) =>
    arxaKitScreenWidthFraction(context, dividedBy: 3);

double arxaKitQuarterScreenWidth(BuildContext context) =>
    arxaKitScreenWidthFraction(context, dividedBy: 4);

double arxaKitGetResponsiveHorizontalSpaceMedium(BuildContext context) =>
    arxaKitScreenWidthFraction(context, dividedBy: 10);
double arxaKitGetResponsiveSmallFontSize(BuildContext context) =>
    arxaKitGetResponsiveFontSize(context, fontSize: 14, max: 15);

double arxaKitGetResponsiveMediumFontSize(BuildContext context) =>
    arxaKitGetResponsiveFontSize(context, fontSize: 16, max: 17);

double arxaKitGetResponsiveLargeFontSize(BuildContext context) =>
    arxaKitGetResponsiveFontSize(context, fontSize: 21, max: 31);

double arxaKitGetResponsiveExtraLargeFontSize(BuildContext context) =>
    arxaKitGetResponsiveFontSize(context, fontSize: 25);

double arxaKitGetResponsiveMassiveFontSize(BuildContext context) =>
    arxaKitGetResponsiveFontSize(context, fontSize: 30);

double arxaKitGetResponsiveFontSize(
  BuildContext context, {
  double? fontSize,
  double? max,
}) {
  max ??= 100;

  var responsiveSize = min(
    arxaKitScreenWidthFraction(context, dividedBy: 10) *
        ((fontSize ?? 100) / 100),
    max,
  );

  return responsiveSize;
}

String arxaKitFormatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
