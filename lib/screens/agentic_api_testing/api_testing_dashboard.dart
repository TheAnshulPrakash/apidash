import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/widgets/widgets.dart';
import 'dart:convert';
import 'widgets/test_plan.dart';
import 'package:http/http.dart' as http;

import 'widgets/agentic_api_testing.dart';

class AgenticAPITestingPage extends ConsumerStatefulWidget {
  const AgenticAPITestingPage({super.key});

  @override
  ConsumerState<AgenticAPITestingPage> createState() =>
      _AgenticAPITestingPageState();
}

enum ActivePane { none, basic, agentic }

class _AgenticAPITestingPageState extends ConsumerState<AgenticAPITestingPage>
    with SingleTickerProviderStateMixin {
  bool _isLoadingTests = false;
  String? _generatedAiText;
  bool optFunctional = true;
  bool optEdgeCases = true;
  bool optErrorHandling = false;
  bool optSecurity = false;
  bool contextBatching = false;

  bool _viewRawJson = false;
  int _dialogKeyCounter = 0;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  ActivePane _activePane = ActivePane.none;

  String? _uploadedFileName;
  String? _uploadedFileContent;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _fadeCtrl.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<String> _fetchTestsFromAi(
      String systemPrompt, String openApiSpec) async {
    final String apiKey = _apiKeyController.text.trim();

    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$apiKey';

    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "system_instruction": {
          "parts": [
            {"text": systemPrompt}
          ]
        },
        "contents": [
          {
            "role": "user",
            "parts": [
              {
                "text":
                    "Here is the OpenAPI specification:\n$openApiSpec\n\nPlease generate the required test JSON."
              }
            ]
          }
        ],
        "generationConfig": {
          "response_mime_type": "application/json",
          "temperature": 0.6,
        }
      }),
    );

    if (res.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(res.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'];

      return text.replaceAll('```json', '').replaceAll('```', '').trim();
    } else {
      throw Exception('Failed to fetch from AI: ${res.body}');
    }
  }

  Future<void> _pickSchemaFile(String selectedId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'yaml', 'yml'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final content = utf8.decode(result.files.single.bytes!);
        setState(() {
          _uploadedFileName = result.files.single.name;
          _uploadedFileContent = content;
        });
        final notifier = ref.read(collectionStateNotifierProvider.notifier);
        final req = notifier.getRequestModel(selectedId);
        final ai = req?.aiRequestModel;
        if (ai != null) {
          notifier.update(aiRequestModel: ai.copyWith(userPrompt: content));
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  void _clearSchemaFile(String selectedId) {
    setState(() {
      _uploadedFileName = null;
      _uploadedFileContent = null;
    });
    final notifier = ref.read(collectionStateNotifierProvider.notifier);
    final req = notifier.getRequestModel(selectedId);
    final ai = req?.aiRequestModel;
    if (ai != null) {
      notifier.update(aiRequestModel: ai.copyWith(userPrompt: ''));
    }
  }

  Future<void> _runBasicTests(BuildContext ctx) async {
    final selectedId = ref.read(selectedIdStateProvider);
    if (selectedId == null) return;

    final req = ref
        .read(collectionStateNotifierProvider.notifier)
        .getRequestModel(selectedId);
    final aiReq = req?.aiRequestModel;

    final systemPrompt =
        aiReq?.systemPrompt ?? 'You are an API execution planner...';
    final openApiSpec = aiReq?.userPrompt ?? _uploadedFileContent;
    debugPrint(systemPrompt);

    if (openApiSpec == null || openApiSpec.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
            content: Text("Please provide an OpenAPI schema first.")),
      );
      return;
    }

    setState(() {
      _isLoadingTests = true;
      _activePane = ActivePane.basic;
      _viewRawJson = false;
      _dialogKeyCounter++;
    });

    try {
      final result = await _fetchTestsFromAi(systemPrompt, openApiSpec);

      setState(() {
        _generatedAiText = result;
      });
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text("Error generating tests: $e")),
      );
      setState(() => _activePane = ActivePane.none);
    } finally {
      setState(() => _isLoadingTests = false);
    }
  }

  void _runAgentic(BuildContext ctx) {
    final schema = _uploadedFileContent;
    if (schema == null || schema.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text("Please upload an OpenAPI schema first.")),
      );
      return;
    }
    setState(() {
      _activePane = ActivePane.agentic;
    });
  }

  Widget _buildRightPane(RequestModel? request) {
    switch (_activePane) {
      case ActivePane.none:
        return Center(
          child: Text(
            'Select "Run Basic Tests" or "Go Agentic!" to start testing.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
        );
      case ActivePane.basic:
        if (_isLoadingTests) {
          return SendingWidget(
            startSendingTime: DateTime.now(),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('UI View')),
                      ButtonSegment<bool>(value: true, label: Text('Raw JSON')),
                    ],
                    selected: {_viewRawJson},
                    onSelectionChanged: (Set<bool> newSelection) {
                      setState(() {
                        _viewRawJson = newSelection.first;
                      });
                    },
                  ),
                  if (!_viewRawJson)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _dialogKeyCounter++;
                        });
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Back to Test Selection'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _viewRawJson
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: SelectableText(
                        _generatedAiText ?? '{}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    )
                  : AIOverlayDialog(
                      key: ValueKey('ai-dialog-$_dialogKeyCounter'),
                      jsonInput: _generatedAiText ?? '{}',
                      endpoint: _urlController.text,
                    ),
            ),
          ],
        );
      case ActivePane.agentic:
        final baseUrl = _urlController.text;
        return AgenticApp(
          openApi: _uploadedFileContent!,
          contextBatching: contextBatching,
          endpoint: baseUrl,
          apiKey: _apiKeyController.text.trim(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedIdStateProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (selectedId == null) {
      return _EmptyState(colorScheme: colorScheme, textTheme: textTheme);
    }

    final request = ref.watch(selectedRequestModelProvider);
    final aiRequestModel = ref
        .watch(selectedRequestModelProvider.select((v) => v?.aiRequestModel));

    String currentSystemPrompt = aiRequestModel?.systemPrompt ??
        r'''You are an expert API test case generator. Your sole purpose is to analyze an OpenAPI specification and output a structured JSON test suite.

Your output will be consumed directly by an automated testing program. Any deviation from the output format will cause a fatal parse error.

════════════════════════════════════════
ABSOLUTE OUTPUT CONTRACT
════════════════════════════════════════
1. Output MUST be valid, parseable JSON.
2. Output MUST begin with `{` and end with `}`.
3. Do NOT wrap output in markdown or code fences (no ``` or ```json).
4. Do NOT include any text, explanation, comment, or whitespace before `{` or after `}`.
5. Do NOT add JSON comments (// or /* */).
6. If you cannot generate tests, still return valid JSON: {"tests": [], "error": "<reason>"}.

════════════════════════════════════════
OUTPUT SCHEMA (follow exactly)
════════════════════════════════════════
{
  "tests": [
    {
      "name": "string — short unique identifier, e.g. GET_users_success",
      "description": "string — what this test validates",
      "method": "GET | POST | PUT | PATCH | DELETE",
      "path": "string — resolved path with path params substituted, e.g. /users/123",
      "path_params": { "key": "value" },
      "query_params": { "key": "value" },
      "headers": { "key": "value" },
      "body": {},
      "expected_status": 200,
      "tags": ["happy_path | edge_case | auth | validation | not_found | server_error"]
    }
  ]
}

All fields are REQUIRED on every test object. Use {} for empty objects and [] for empty arrays.

════════════════════════════════════════
TEST GENERATION RULES
════════════════════════════════════════
Coverage requirements:
- Generate a MINIMUM of 10 test cases total.
- Every endpoint in the spec MUST have at least one test.
- Every endpoint MUST have both a happy path (2xx) and at least one failure case.

For each endpoint, generate tests across these categories where applicable:
  Happy path         — valid inputs, expected 2xx response
  Validation error   — missing required fields, wrong types → expect 400
  Unauthorized       — missing or invalid auth token → expect 401
  Forbidden          — valid token but insufficient permissions → expect 403
  Not found          — valid format but non-existent resource ID → expect 404
  Edge cases         — boundary values, empty strings, max-length inputs, special characters

Dummy data rules:
- Use realistic-looking dummy values (e.g. "john.doe@example.com", not "aaa@bbb").
- UUIDs must follow format: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
- Dates must follow ISO 8601: "2024-06-15T10:30:00Z"
- Path parameters MUST be substituted into the path string AND included in path_params.
- If an endpoint requires auth, include: "Authorization": "Bearer test-token-valid" for valid cases and "Authorization": "Bearer invalid-token" for auth failure cases.
- For invalid/missing body tests, deliberately omit required fields or use wrong types (e.g. pass a string where an integer is expected).


<INSERT OPENAPI SPEC HERE>''';
    final userPrompt = ref.watch(selectedRequestModelProvider
        .select((v) => v?.aiRequestModel?.userPrompt));

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!context.isMediumWindow)
            Row(
              children: [
                _PageHeader(colorScheme: colorScheme, textTheme: textTheme),
                Spacer(),
                Expanded(
                  child: _ApiKeyField(
                    controller: _apiKeyController,
                  ),
                )
              ],
            ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // left pane config
                Expanded(
                  flex: 1,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    children: [
                      _SectionHeader(
                        title: 'Agent Context Source',
                        subtitle:
                            'Define how the AI maps the API. Provide a full OpenAPI schema for deterministic, context-aware generation.',
                      ),
                      kVSpacer10,
                      _UrlField(controller: _urlController),
                      kVSpacer10,
                      _SchemaUploadField(
                        fileName: _uploadedFileName,
                        onPick: () => _pickSchemaFile(selectedId),
                        onClear: () => _clearSchemaFile(selectedId),
                      ),
                      kVSpacer10,
                      _ContextBatchingTile(
                        value: contextBatching,
                        onChanged: (v) =>
                            setState(() => contextBatching = v ?? false),
                      ),
                      kVSpacer20,
                      _SectionHeader(
                        title: 'Select AI Tests',
                        subtitle:
                            'Configure autonomous testing constraints. The agent will generate workflows and assertions based on these parameters.',
                      ),
                      kVSpacer10,
                      _TestOptionsCard(
                        optFunctional: optFunctional,
                        optEdgeCases: optEdgeCases,
                        optErrorHandling: optErrorHandling,
                        optSecurity: optSecurity,
                        onFunctional: (v) =>
                            setState(() => optFunctional = v ?? true),
                        onEdgeCases: (v) =>
                            setState(() => optEdgeCases = v ?? true),
                        onErrorHandling: (v) =>
                            setState(() => optErrorHandling = v ?? false),
                        onSecurity: (v) =>
                            setState(() => optSecurity = v ?? false),
                      ),
                      kVSpacer20,
                      _ActionButtons(
                        onRunBasic: () => _runBasicTests(
                          context,
                        ),
                        onAgentic: () => _runAgentic(context),
                      ),
                      kVSpacer20,
                      _SectionHeader(
                        title: 'Manual Overrides',
                        subtitle:
                            'Provide custom rules or headers to guide the agent\'s generation logic.',
                      ),
                      kVSpacer10,
                      _ManualOverridesRow(
                        selectedId: selectedId,
                        aiRequestModel: aiRequestModel,
                        systemPrompt: currentSystemPrompt,
                        userPrompt: userPrompt,
                        ref: ref,
                      ),
                    ],
                  ),
                ),

                // RIGHT pane config
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: _buildRightPane(request),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colorScheme, required this.textTheme});
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 72, color: colorScheme.primary.withAlpha(90)),
          kVSpacer20,
          Text('Agentic API Testing', style: textTheme.headlineMedium),
          kVSpacer10,
          Text(
            'Select a request to get started',
            style: textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurface.withAlpha(140)),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyField extends StatelessWidget {
  const _ApiKeyField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(
          hintText: 'Enter your Gemini API Key',
          prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.colorScheme, required this.textTheme});
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: kPh20v10,
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 28, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text('Agentic API Testing', style: textTheme.headlineLarge),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurface.withAlpha(150))),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrlField extends StatelessWidget {
  const _UrlField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Target API URL (e.g., https://localhost:8000)',
          prefixIcon: const Icon(Icons.http, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}

class _SchemaUploadField extends StatelessWidget {
  const _SchemaUploadField(
      {required this.fileName, required this.onPick, required this.onClear});
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        readOnly: true,
        controller: TextEditingController(text: fileName ?? ''),
        decoration: InputDecoration(
          hintText: 'Upload local .yaml or .json schema file',
          prefixIcon: const Icon(Icons.data_object, size: 20),
          suffixIcon: fileName != null
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                  onPressed: onClear,
                  tooltip: 'Remove file',
                )
              : IconButton(
                  icon: const Icon(Icons.folder_open,
                      color: Colors.blue, size: 20),
                  onPressed: onPick,
                  tooltip: 'Browse local files',
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: fileName != null,
          fillColor: fileName != null
              ? const Color.fromRGBO(33, 150, 243, 0.06)
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}

class _ContextBatchingTile extends StatelessWidget {
  const _ContextBatchingTile({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        border: Border.all(
            color: value
                ? colorScheme.primary.withAlpha(120)
                : Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
        color: value ? colorScheme.primaryContainer.withAlpha(50) : null,
      ),
      child: SwitchListTile(
        title: const Text('Enable OpenAPI Context Batching',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
            'Significantly reduce token consumption and hallucination',
            style: TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
        secondary: Icon(
          Icons.compress_outlined,
          color: value
              ? colorScheme.primary
              : colorScheme.onSurface.withAlpha(120),
        ),
      ),
    );
  }
}

class _TestOptionsCard extends StatelessWidget {
  const _TestOptionsCard({
    required this.optFunctional,
    required this.optEdgeCases,
    required this.optErrorHandling,
    required this.optSecurity,
    required this.onFunctional,
    required this.onEdgeCases,
    required this.onErrorHandling,
    required this.onSecurity,
  });

  final bool optFunctional;
  final bool optEdgeCases;
  final bool optErrorHandling;
  final bool optSecurity;
  final ValueChanged<bool?> onFunctional;
  final ValueChanged<bool?> onEdgeCases;
  final ValueChanged<bool?> onErrorHandling;
  final ValueChanged<bool?> onSecurity;

  @override
  Widget build(BuildContext context) {
    final options = [
      _TestOption(
        icon: Icons.check_circle_outline,
        title: 'Functional Correctness',
        subtitle: 'Generate standard valid JSON payloads & 200 OK assertions.',
        value: optFunctional,
        onChanged: onFunctional,
        accentColor: Colors.green,
      ),
      _TestOption(
        icon: Icons.tune,
        title: 'Edge Cases & Boundaries',
        subtitle: 'Inject boundary values and null states into parameters.',
        value: optEdgeCases,
        onChanged: onEdgeCases,
        accentColor: Colors.orange,
      ),
      _TestOption(
        icon: Icons.healing_outlined,
        title: 'Auto-Correction (Self-Healing)',
        subtitle:
            'Agent intercepts 4xx/5xx errors and attempts to patch schemas confirming from the user. (Agentic)',
        value: optErrorHandling,
        onChanged: onErrorHandling,
        accentColor: Colors.blue,
      ),
      _TestOption(
        icon: Icons.shield_outlined,
        title: 'Security Validation',
        subtitle:
            'Test for missing auth headers and basic workflow vulnerabilities.',
        value: optSecurity,
        onChanged: onSecurity,
        accentColor: Colors.red,
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: options.asMap().entries.map((entry) {
          final i = entry.key;
          final opt = entry.value;
          return Column(
            children: [
              _TestOptionTile(opt: opt),
              if (i < options.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _TestOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final Color accentColor;

  const _TestOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accentColor,
  });
}

class _TestOptionTile extends StatelessWidget {
  const _TestOptionTile({required this.opt});
  final _TestOption opt;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      secondary: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: opt.value ? opt.accentColor.withAlpha(35) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(opt.icon,
            size: 20,
            color: opt.value
                ? opt.accentColor
                : Theme.of(context).colorScheme.onSurface.withAlpha(100)),
      ),
      title: Text(opt.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(opt.subtitle, style: const TextStyle(fontSize: 12)),
      value: opt.value,
      onChanged: opt.onChanged,
      shape: const RoundedRectangleBorder(),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onRunBasic, required this.onAgentic});
  final VoidCallback onRunBasic;
  final VoidCallback onAgentic;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Generate Tests',
            sublabel: 'AI-generated Tests',
            onPressed: onRunBasic,
            isPrimary: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.smart_toy_rounded,
            label: 'Go Agentic !',
            sublabel: 'Chat with your API.',
            onPressed: onAgentic,
            isPrimary: true,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onPressed,
    required this.isPrimary,
  });
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        minimumSize: const Size(double.infinity, 60),
        backgroundColor: isPrimary
            ? colorScheme.primaryContainer
            : colorScheme.secondaryContainer,
        foregroundColor: isPrimary
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSecondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text(sublabel, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualOverridesRow extends StatelessWidget {
  const _ManualOverridesRow({
    required this.selectedId,
    required this.aiRequestModel,
    required this.systemPrompt,
    required this.userPrompt,
    required this.ref,
  });

  final String selectedId;
  final dynamic aiRequestModel;
  final String? systemPrompt;
  final String? userPrompt;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PromptField(
            label: 'Update Prompt',
            hint: 'Enter custom System Prompt or select Tests',
            fieldKey: '$selectedId-aireq-sysprompt-body',
            initialValue: systemPrompt,
            onChanged: (v) {
              final currentModel = aiRequestModel ?? const AIRequestModel();
              ref.read(collectionStateNotifierProvider.notifier).update(
                    aiRequestModel: currentModel.copyWith(systemPrompt: v),
                  );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _PromptField(
            label: 'OpenAPI JSON/YAML',
            hint: 'Enter OpenAPI',
            fieldKey: '$selectedId-aireq-userprompt-body',
            initialValue: userPrompt,
            onChanged: (v) {
              final currentModel = aiRequestModel ?? const AIRequestModel();
              ref.read(collectionStateNotifierProvider.notifier).update(
                    aiRequestModel: currentModel.copyWith(userPrompt: v),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.label,
    required this.hint,
    required this.fieldKey,
    required this.initialValue,
    required this.onChanged,
  });
  final String label;
  final String hint;
  final String fieldKey;
  final String? initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.open_in_full, size: 14),
              tooltip: 'Edit in fullscreen',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(label),
                    content: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: TextFieldEditor(
                        fieldKey: '${fieldKey}_overlay',
                        initialValue: initialValue,
                        onChanged: onChanged,
                        hintText: hint,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 130,
          child: TextFieldEditor(
            key: Key(fieldKey),
            fieldKey: fieldKey,
            initialValue: initialValue,
            onChanged: onChanged,
            hintText: hint,
          ),
        ),
      ],
    );
  }
}
