// arxa-builder: LIVE — tablet layout of the code sessions list (centered
// at a readable width).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelWidget;
import 'package:flutter/material.dart';

import 'code_sessions_body.dart';
import 'code_sessions_viewmodel.dart';

class CodeSessionsViewTablet extends ViewModelWidget<CodeSessionsViewModel> {
  const CodeSessionsViewTablet({super.key, required this.viewModel});

  final CodeSessionsViewModel viewModel;

  @override
  Widget build(context, _) =>
      CodeSessionsBody(key: key, viewModel: viewModel, constrainWidth: true);
}
