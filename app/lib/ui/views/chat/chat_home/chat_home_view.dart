import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/ui/common/app_box_widgets.dart';
import 'chat_home_viewmodel.dart';

class ChatHomeView extends StackedView<ChatHomeViewModel> {
  const ChatHomeView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StateChip(switch (viewModel.state) {
              ChatState.idle => 'Idle',
              ChatState.streaming => 'Streaming',
              ChatState.toolCall => 'Tool-call',
              ChatState.noServers => 'No servers',
            })),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Text('${viewModel.toolCount} tools', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            TextButton.icon(
              onPressed: viewModel.connect,
              icon: const Icon(Icons.cable),
              label: const Text('Connect'),
            ),
          ]),
        ),
        Expanded(
          child: viewModel.log.isEmpty
              ? const EmptyState(
                  title: 'No conversation yet',
                  body: 'Connect to an MCP server and drive the pipeline by chat. '
                      'Tools from every connected server combine into one registry.')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [for (final line in viewModel.log) ListTile(dense: true, title: Text(line))],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(hintText: 'Message…', border: OutlineInputBorder()),
                onChanged: viewModel.onDraft,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: viewModel.state == ChatState.streaming ? null : viewModel.send,
              child: const Icon(Icons.send),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  ChatHomeViewModel viewModelBuilder(context) => ChatHomeViewModel();
}
