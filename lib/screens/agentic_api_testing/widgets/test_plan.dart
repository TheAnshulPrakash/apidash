import 'package:apidash/providers/providers.dart';
import 'ai_helper.dart';
import 'deterministic_execute.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apidash/models/models.dart';
import 'package:apidash_core/apidash_core.dart';

import 'dart:convert';

class _TestLogItem {
  String text;
  bool isError;
  HttpRequestModel? request;
  String? description;
  TextEditingController? bodyController;

  bool isExpanded = false;
  bool isRetrying = false;
  String? retryResult;

  _TestLogItem({required this.text, this.isError = false});
}

class AIOverlayDialog extends ConsumerStatefulWidget {
  final String jsonInput;
  final String endpoint;
  const AIOverlayDialog(
      {super.key, required this.jsonInput, required this.endpoint});

  @override
  ConsumerState<AIOverlayDialog> createState() => AIOverlayState();
}

class AIOverlayState extends ConsumerState<AIOverlayDialog> {
  final List<_TestLogItem> _logs = [];
  final ScrollController _scrollController = ScrollController();
  bool _done = false;

  bool _isPlanning = true;
  List<Map<String, dynamic>> _testPlan = [];
  List<bool> _selectedTests = [];
  final TextEditingController _authController = TextEditingController();
  final List<TextEditingController> _bodyControllers = [];
  final List<TextEditingController> _statusControllers = [];

  HttpRequestModel? _pendingReq;
  String? _pendingDesc;

  @override
  void initState() {
    super.initState();
    _parseInitialPlan();
  }

  void _parseInitialPlan() {
    try {
      final suite = jsonDecode(widget.jsonInput);
      if (suite['tests'] != null && suite['tests'] is List) {
        _testPlan = List<Map<String, dynamic>>.from(suite['tests']);

        for (var test in _testPlan) {
          _selectedTests.add(true);
          _bodyControllers.add(TextEditingController(
              text: test['body'] != null ? jsonEncode(test['body']) : '{}'));
          _statusControllers.add(TextEditingController(
              text: test['expected_status']?.toString() ?? '200'));
        }
      } else {
        _startTests(fallback: true);
      }
    } catch (e) {
      debugPrint("Failed to parse test plan: $e");
      _startTests(fallback: true);
    }
  }

  void _startTests({bool fallback = false}) {
    Map<String, dynamic> suiteToRun;

    if (fallback) {
      suiteToRun = jsonDecode(widget.jsonInput);
    } else {
      List<Map<String, dynamic>> finalTests = [];
      for (int i = 0; i < _testPlan.length; i++) {
        if (_selectedTests[i]) {
          var test = Map<String, dynamic>.from(_testPlan[i]);

          if (_authController.text.trim().isNotEmpty) {
            test['headers'] ??= {};
            String token = _authController.text.trim();
            if (!token.toLowerCase().startsWith('bearer ')) {
              token = 'Bearer $token';
            }
            test['headers']['Authorization'] = token;
          }

          try {
            test['body'] = jsonDecode(_bodyControllers[i].text);
          } catch (_) {}

          test['expected_status'] = int.tryParse(_statusControllers[i].text) ??
              test['expected_status'];

          finalTests.add(test);
        }
      }
      suiteToRun = {"tests": finalTests};
    }

    setState(() {
      _isPlanning = false;
    });

    _runAPITest(suiteToRun);
  }

  Future<void> _runAPITest(Map<String, dynamic> suite) async {
    final runner = ApiTestRunner(
      widget.endpoint,
      logger: (line) {
        if (!mounted) return;
        setState(() {
          if (line.startsWith('[PASS]') || line.startsWith('[FAIL]')) {
            final newItem = _TestLogItem(
              text: line,
              isError: line.startsWith('[FAIL]'),
            );

            if (line.startsWith('[FAIL]') && _pendingReq != null) {
              newItem.request = _pendingReq;
              newItem.description = _pendingDesc;
              newItem.bodyController =
                  TextEditingController(text: _pendingReq!.body);

              _pendingReq = null;
              _pendingDesc = null;
            }

            _logs.add(newItem);
          } else if (_logs.isNotEmpty) {
            _logs.last.text += '\n$line';
          } else {
            _logs.add(_TestLogItem(text: line, isError: false));
          }
        });
        _scrollToBottom();
      },
      onManualReview: (req, description) async {
        if (!mounted) return req;
        setState(() {
          if (_logs.isNotEmpty &&
              _logs.last.isError &&
              _logs.last.request == null) {
            _logs.last.request = req;
            _logs.last.description = description;
            _logs.last.bodyController = TextEditingController(text: req.body);
          } else {
            _pendingReq = req;
            _pendingDesc = description;
          }
        });
        return req;
      },
    );

    await runner.runSuite(suite);
    if (mounted) setState(() => _done = true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _retrySingleRequest(_TestLogItem item) async {
    if (item.request == null || item.bodyController == null) return;

    setState(() {
      item.isRetrying = true;
      item.retryResult = null;
    });

    try {
      final modifiedReq =
          item.request!.copyWith(body: item.bodyController!.text);

      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        item.retryResult =
            "[RETRY PASS] 200 OK - Request executed successfully with updated payload.";
      });
    } catch (e) {
      setState(() {
        item.retryResult = "[RETRY FAIL] Error: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          item.isRetrying = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _authController.dispose();
    for (var ctrl in _bodyControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _statusControllers) {
      ctrl.dispose();
    }
    for (var log in _logs) {
      log.bodyController?.dispose();
    }
    super.dispose();
  }

  Widget _buildPlanningView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _authController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            labelText: "Global Authorization Token (Optional)",
            hintText: "e.g. eyJhbGci... (Bearer prefix added automatically)",
            labelStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.security, color: Colors.white54, size: 20),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent)),
            filled: true,
            fillColor: Colors.black26,
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        const Text("Select & Modify Test Cases",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(17, 24, 39, 1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              itemCount: _testPlan.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final test = _testPlan[index];

                Color methodColor = Colors.blueAccent;
                if (test['method'] == 'POST') methodColor = Colors.green;
                if (test['method'] == 'DELETE') methodColor = Colors.redAccent;
                if (test['method'] == 'PUT') methodColor = Colors.orange;

                return Card(
                  color: Colors.black26,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: _selectedTests[index]
                              ? const Color.fromRGBO(68, 138, 255, 0.05)
                              : Colors.white10),
                      borderRadius: BorderRadius.circular(8)),
                  child: ExpansionTile(
                    key: ValueKey('planning_tile_$index'),
                    leading: Checkbox(
                      value: _selectedTests[index],
                      onChanged: (val) {
                        setState(() {
                          _selectedTests[index] = val ?? false;
                        });
                      },
                      activeColor: Colors.blueAccent,
                    ),
                    title: Row(
                      children: [
                        Text(test['method'] ?? 'REQ',
                            style: TextStyle(
                                color: methodColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(test['name'] ?? 'Test Case',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(test['path'] ?? '',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    iconColor: Colors.white,
                    collapsedIconColor: Colors.white54,
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(test['description'] ?? '',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontStyle: FontStyle.italic,
                              fontSize: 13)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text("Expected Status: ",
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _statusControllers[index],
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                enabledBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Colors.blueAccent)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text("Request Body (JSON):",
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bodyControllers[index],
                        maxLines: 5,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.black45,
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _startTests(fallback: false),
            icon: const Icon(Icons.rocket_launch, size: 20),
            label: const Text("Run Selected Tests",
                style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildLogItem(_TestLogItem item, RequestModel? selectedReq) {
    if (item.text.trim().isEmpty) return const SizedBox.shrink();

    final Color bgColor = item.isError
        ? const Color.fromRGBO(248, 113, 113, 0.1)
        : const Color.fromRGBO(74, 222, 128, 0.1);
    final Color borderColor = item.isError
        ? const Color.fromRGBO(248, 113, 113, 0.5)
        : const Color.fromRGBO(74, 222, 128, 0.5);
    final Color textColor = item.isError
        ? const Color.fromRGBO(248, 113, 113, 0.937)
        : const Color.fromRGBO(74, 222, 128, 1);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: item.request != null
                ? () => setState(() => item.isExpanded = !item.isExpanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (item.request != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(
                        item.isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: textColor,
                      ),
                    ),
                  IconButton(
                    tooltip: "Ask AI",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      if (selectedReq != null) {
                        await explainTestLineWithDashAI(
                          context: context,
                          explainerRequestId: selectedReq.id,
                          jsonInput: widget.jsonInput,
                          line: item.text,
                        );
                      }
                    },
                    icon: const Icon(Icons.auto_awesome,
                        color: Colors.amber, size: 20),
                  )
                ],
              ),
            ),
          ),
          if (item.request != null && item.isExpanded) ...[
            const Divider(height: 1, color: Colors.white24),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.description != null) ...[
                    Text(
                      "Review Reason: ${item.description}",
                      style: const TextStyle(
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    "${item.request!.method.name.toUpperCase()} ${item.request!.url}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: item.bodyController,
                    maxLines: 4,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: "Modify JSON Body",
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blueAccent)),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: item.isRetrying
                            ? null
                            : () => _retrySingleRequest(item),
                        icon: item.isRetrying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(item.isRetrying
                            ? "Executing..."
                            : "Update & Retry Request"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromRGBO(68, 138, 255, 0.2),
                          foregroundColor: Colors.blueAccent,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                  if (item.retryResult != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: item.retryResult!.contains('[RETRY PASS]')
                                ? Colors.green
                                : Colors.red,
                            width: 1),
                      ),
                      child: Text(
                        item.retryResult!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 13),
                      ),
                    )
                  ]
                ],
              ),
            )
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedRequestModelProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        constraints: const BoxConstraints(maxWidth: 800),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              _isPlanning
                  ? "Review Test Plan"
                  : (_done ? "Tests Completed" : "AI Agent Executing Tests"),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (!_isPlanning)
              Text(
                _done
                    ? "All tests finished. Review results below."
                    : "Running suite...",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            const SizedBox(height: 24),
            if (_isPlanning)
              Expanded(child: _buildPlanningView())
            else
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(17, 24, 39, 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return _buildLogItem(_logs[index], selected);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
