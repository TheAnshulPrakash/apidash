import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apidash/providers/providers.dart';

Future<void> explainTestLineWithDashAI({
  required BuildContext context,
  required String explainerRequestId,
  required String jsonInput,
  required String line,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExplainDialog(
      explainerRequestId: explainerRequestId,
      jsonInput: jsonInput,
      line: line,
    ),
  );
}

class _ExplainDialog extends ConsumerStatefulWidget {
  final String explainerRequestId, jsonInput, line;

  const _ExplainDialog({
    required this.explainerRequestId,
    required this.jsonInput,
    required this.line,
  });

  @override
  ConsumerState<_ExplainDialog> createState() => _ExplainDialogState();
}

class _ExplainDialogState extends ConsumerState<_ExplainDialog> {
  String? _result, _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final notifier = ref.read(collectionStateNotifierProvider.notifier);
      final req = notifier.getRequestModel(widget.explainerRequestId);
      final ai = req?.aiRequestModel;

      if (req == null || ai == null)
        throw Exception('Explainer request not found.');

      ref.read(selectedIdStateProvider.notifier).state =
          widget.explainerRequestId;

      notifier.update(
        aiRequestModel: ai.copyWith(
          systemPrompt:
              'You are an API testing assistant. Explain test failures with: probable cause, evidence, and next steps. Be concise.',
          userPrompt:
              'Test suite JSON:\n${widget.jsonInput}\n\nLog line:\n${widget.line}\n\nExplain what happened and how to fix it.',
        ),
      );

      await notifier.sendRequest();

      final updated = notifier.getRequestModel(widget.explainerRequestId);
      final text = updated?.httpResponseModel?.formattedBody ??
          updated?.httpResponseModel?.body;
      debugPrint('[AI_EXPLAIN] ${text ?? "<empty>"}');

      if (mounted) {
        setState(() {
          _result = text?.trim() ?? 'No response.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text('DashAI Explanation',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Text(
                  _error != null ? '$_error' : _result!,
                  style: TextStyle(
                    color: _error != null
                        ? Colors.redAccent
                        : const Color(0xFFCDD6F4),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
      ),
      actions: [
        if (!_loading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
      ],
    );
  }
}
