import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

class ShowcaseTextInputDialogModel extends BaseViewModel {
  ShowcaseTextInputDialogModel(String? initial)
      : controller = TextEditingController(text: initial);

  final TextEditingController controller;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
