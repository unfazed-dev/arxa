import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'startup_splash.dart';
import 'startup_viewmodel.dart';

class StartupViewDesktop extends ViewModelWidget<StartupViewModel> {
  const StartupViewDesktop({super.key});

  @override
  Widget build(BuildContext context, StartupViewModel viewModel) =>
      const StartupSplash();
}
