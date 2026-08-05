import 'package:flutter/material.dart';
import 'package:appbox_kit_showcase_app/ui/common/app_colors.dart';
import 'package:appbox_kit_showcase_app/ui/common/ui_helpers.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:appbox_kit_showcase_app/ui/bottom_sheets/showcase_notice_sheet/showcase_notice_sheet_model.dart';

class ShowcaseNoticeSheet extends StackedView<ShowcaseShowcaseNoticeSheetModel> {
  final Function(SheetResponse)? completer;
  final SheetRequest request;
  const ShowcaseNoticeSheet(
      {super.key, required this.completer, required this.request});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseShowcaseNoticeSheetModel viewModel,
    Widget? child,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: kcWhite,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            request.title!,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          verticalSpaceTiny,
          Text(
            request.description!,
            style: const TextStyle(fontSize: 14, color: kcMediumGrey),
            maxLines: 3,
            softWrap: true,
          ),
          verticalSpaceLarge,
        ],
      ),
    );
  }

  @override
  ShowcaseShowcaseNoticeSheetModel viewModelBuilder(BuildContext context) => ShowcaseShowcaseNoticeSheetModel();
}
