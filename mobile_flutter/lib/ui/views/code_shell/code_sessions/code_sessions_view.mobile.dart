// arxa-builder: LIVE — mobile layout of the code sessions list.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;
import 'package:flutter/material.dart';

import 'code_sessions_body.dart';
import 'code_sessions_viewmodel.dart';

class CodeSessionsViewMobile extends ViewModelWidget<CodeSessionsViewModel> {
  const CodeSessionsViewMobile({super.key, required this.viewModel});

  final CodeSessionsViewModel viewModel;

  @override
  Widget build(context, _) => CodeSessionsBody(key: key, viewModel: viewModel);
}
