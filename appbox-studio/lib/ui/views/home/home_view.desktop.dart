import 'package:appbox_studio/l10n/app_localizations.dart';
import 'package:appbox_studio/ui/common/app_colors.dart';
import 'package:appbox_studio/ui/common/app_constants.dart';
import 'package:appbox_studio/ui/common/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'home_viewmodel.dart';

class HomeViewDesktop extends ViewModelWidget<HomeViewModel> {
  const HomeViewDesktop({super.key});

  @override
  Widget build(BuildContext context, HomeViewModel viewModel) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: kdDesktopMaxContentWidth,
          height: kdDesktopMaxContentHeight,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              verticalSpaceLarge,
              Column(
                children: [
                  Text(
                    l10n.homeGreetingDesktop,
                    style: const TextStyle(fontSize: 35, fontWeight: FontWeight.w900),
                  ),
                  verticalSpaceMedium,
                  MaterialButton(
                    color: Colors.black,
                    onPressed: viewModel.incrementCounter,
                    child: Text(
                      viewModel.counterLabel,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MaterialButton(
                    color: kcDarkGreyColor,
                    onPressed: viewModel.showDialog,
                    child: Text(
                      l10n.homeShowDialog,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  MaterialButton(
                    color: kcDarkGreyColor,
                    onPressed: viewModel.showBottomSheet,
                    child: Text(
                      l10n.homeShowBottomSheet,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
