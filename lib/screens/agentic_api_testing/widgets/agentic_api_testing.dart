import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'openapi_Context_Parsing.dart';

class ApiMessage {
  final String role;
  final String content;
  final Map<String, dynamic>? apiJson;
  final int? inputWords;
  final int? outputWords;

  ApiMessage({
    required this.role,
    required this.content,
    this.apiJson,
    this.inputWords,
    this.outputWords,
  });
}

class OpenApiAgent extends ChangeNotifier {
  final String model = 'gpt-oss:20b';
  final String openApiSpec;
  final String endpoint;
  final String apiKey;
  int totalInputWords = 0;
  int totalOutputWords = 0;
  final List<ApiMessage> messages = [];
  bool isLoading = false;
  late String currentActiveSpec;

  OpenApiAgent(
      {required this.openApiSpec,
      required this.endpoint,
      required this.apiKey}) {
    currentActiveSpec = openApiSpec;
    _systemPrompt();
  }
  void updateContext(Map<String, dynamic> batch, {bool isBatched = true}) {
    currentActiveSpec = jsonEncode(batch);

    messages.clear();

    _systemPrompt();

    if (isBatched) {
      messages.add(ApiMessage(
          role: 'system',
          content:
              "🔄 Scope locked to specific module. Only the relevant endpoints are now loaded."));
    } else {
      messages.add(ApiMessage(
          role: 'system',
          content: "🔄 Using full OpenAPI specification scope."));
    }
    notifyListeners();
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  void _systemPrompt() {
    messages.add(
      ApiMessage(
        role: 'system',
        content: '''You are an API execution planner.

Your job is to analyze a provided OpenAPI specification and help the user interact with the API in an Agentic way step-by-step by crafting http requests.

Behavior rules:

1. Carefully read the OpenAPI specification.
2. Determine the correct sequence of HTTP calls required to fulfill the user's request.
3. Produce ONE request at a time.
4. Always return your response strictly as JSON.
5. Do NOT produce explanations outside JSON.
6. Check root "/" if user greets and no healthcheck function is present

STRICT OPERATIONAL RULES:
1. NO INFERENCE: Do not assume an endpoint exists (like DELETE or PUT) just because it is common. If it is not in the "paths" object of the spec, it does not exist.
2. PATH VERIFICATION: Before generating a request, find the exact path string in the spec.
3. SCHEMA ADHERENCE: Request bodies MUST exactly match the "components/schemas" defined.
4. ERROR HANDLING: If the user asks for an action that is not supported by the OpenAPI spec (e.g., Deleting when no DELETE path is defined), respond with a JSON description explaining that the operation is not supported by the API.
5. SEMANTIC MATCHING: Thoroughly check the "summary" and "description" fields of every endpoint in the OpenAPI spec. Use these to map the user's natural language intent to the correct path, even if the path name itself is not an exact match.

Each response must contain the following fields:

{
  "description": "Human readable explanation of what this request does",
  "request": {
    "method": "GET | POST | PUT | PATCH | DELETE",
    "path": "exact path from spec",
    "headers": {
      "Content-Type": "application/json"
    },
    "query_params": {},
    "body": {},
  },
  "is_last": false,
  "next_prompt": "Ask the user if they want to continue with the next request from openAPI or perform a custom action."
}

Important rules:

- Only generate ONE HTTP request per response.
- `is_last` must be true only when the task is complete.
- If the API requires parameters that the user has not provided, take related dummy values.
- If the workflow requires multiple steps (for example: create user → add book → borrow book), plan them sequentially.
''',
      ),
    );
  }

  Future<void> processStep(String userInstruction) async {
    if (userInstruction.isEmpty) return;

    isLoading = true;
    notifyListeners();

    messages.add(ApiMessage(role: 'user', content: userInstruction));

    await retryLoop(retryCount: 0);

    isLoading = false;
    notifyListeners();
  }

  Future<void> retryLoop({required int retryCount}) async {
    const int maxRetries = 3; // We can modify this based on the request type

    try {
      final result = await fetchOllama();
      final aiRaw = result.$1;
      final inputWords = result.$2;
      final outputWords = result.$3;

      final Map<String, dynamic> plan = jsonDecode(_cleanJson(aiRaw));

      messages.add(
        ApiMessage(
          role: 'DashBot',
          content: plan['description'],
          apiJson: plan,
          inputWords: inputWords,
          outputWords: outputWords,
        ),
      );
      notifyListeners();

      final reqData = plan['request'];
      final url = Uri.parse("$endpoint${reqData['path']}");

      messages.add(
        ApiMessage(
          role: 'system',
          content:
              "⏳ [Attempt ${retryCount + 1}] ${reqData['method']} ${reqData['path']}",
        ),
      );
      notifyListeners();

      final response = await _makeHttpRequest(url, reqData);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        messages.add(
          ApiMessage(
            role: 'system',
            content: "✅ PASS (${response.statusCode})",
          ),
        );
        messages.add(
          ApiMessage(
            role: 'system',
            content:
                "Successful. Response: ${response.body}. What's the next step?",
          ),
        );
      } else {
        messages.add(
          ApiMessage(
            role: 'system',
            content: "❌ FAIL (${response.statusCode})",
          ),
        );

        if (retryCount < maxRetries) {
          messages.add(
            ApiMessage(
              role: 'system',
              content:
                  "The API returned an error: ${response.statusCode} - ${response.body}. Please fix the parameters, analyze the OpenAPI and comment if that command exists and try again.",
            ),
          );
          await retryLoop(retryCount: retryCount + 1);
        } else {
          messages.add(
            ApiMessage(
              role: 'system',
              content:
                  "🛑 TERMINATED: Failed after $maxRetries retries. Reason: AI could not satisfy the API schema constraints.",
            ),
          );
        }
      }
    } catch (e) {
      messages.add(ApiMessage(role: 'system', content: "⚠️ Local Error: $e"));
    }
    notifyListeners();
  }

  Future<http.Response> _makeHttpRequest(
    Uri url,
    Map<String, dynamic> reqData,
  ) async {
    final method = reqData['method'].toString().toUpperCase();
    final headers = Map<String, String>.from(reqData['headers'] ?? {});
    final body = jsonEncode(reqData['body'] ?? {});

    switch (method) {
      case 'POST':
        return await http.post(url, headers: headers, body: body);
      case 'PUT':
        return await http.put(url, headers: headers, body: body);
      case 'PATCH':
        return await http.patch(url, headers: headers, body: body);
      case 'DELETE':
        return await http.delete(url, headers: headers, body: body);
      default:
        return await http.get(url, headers: headers);
    }
  }

  Future<(String, int, int)> fetchOllama() async {
    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$apiKey';

    int currentRequestInputWords = 0;
    currentRequestInputWords += _countWords(
        "SYSTEM INSTRUCTION: CURRENT API SCOPE: $currentActiveSpec");
    for (var m in messages) {
      currentRequestInputWords += _countWords(m.content);
    }

    print(currentActiveSpec);

    final contents = [
      {
        "role": "user",
        "parts": [
          {"text": "SYSTEM INSTRUCTION: CURRENT API SCOPE: $currentActiveSpec"}
        ]
      },
      ...messages
          .map((m) => {
                "role": m.role == 'DashBot' ? 'model' : 'user',
                "parts": [
                  {"text": m.content}
                ]
              })
          .toList(),
    ];

    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": contents,
        "generationConfig": {
          "response_mime_type": "application/json",
          "temperature": 0.7,
        }
      }),
    );

    if (res.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(res.body);
      final String aiResponse =
          data['candidates'][0]['content']['parts'][0]['text'];

      print("AI Returned");
      int currentRequestOutputWords = _countWords(aiResponse);

      totalInputWords += currentRequestInputWords;
      totalOutputWords += currentRequestOutputWords;

      debugPrint('--- AI Usage Stats ---');
      debugPrint('Input Words (This trip): $currentRequestInputWords');
      debugPrint('Output Words (This trip): $currentRequestOutputWords');
      debugPrint('Total Session Words: ${totalInputWords + totalOutputWords}');
      debugPrint('--------------------f--');

      return (aiResponse, currentRequestInputWords, currentRequestOutputWords);
    } else {
      throw Exception('Failed to fetch from Google AI: ${res.body}');
    }
  }

  String _cleanJson(String raw) =>
      raw.replaceAll('```json', '').replaceAll('```', '').trim();
}

// void main() => runApp(
//   MaterialApp(
//     home: AgenticApp(),
//     theme: ThemeData.dark().copyWith(
//       scaffoldBackgroundColor: const Color(0xFF121212),
//     ),
//     debugShowCheckedModeBanner: false,
//   ),
// );

class AgenticApp extends StatefulWidget {
  final String openApi;
  final String endpoint;
  final bool contextBatching;
  final String apiKey;

  const AgenticApp({
    super.key,
    required this.openApi,
    required this.endpoint,
    required this.contextBatching,
    required this.apiKey,
  });
  @override
  State<AgenticApp> createState() => _AgenticAppState();
}

class _AgenticAppState extends State<AgenticApp> {
  late OpenApiAgent agent;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Map<String, Map<String, dynamic>> featureBatches = {};

  @override
  void initState() {
    super.initState();
    print(widget.openApi);
    final Map<String, dynamic> spec = jsonDecode(widget.openApi);
    final Map<String, dynamic> allPaths = spec['paths'] ?? {};
    final Map<String, dynamic> allSchemas =
        spec['components']?['schemas'] ?? {};

    allPaths.forEach((pathKey, pathData) {
      final segments = pathKey.split('/').where((s) => s.isNotEmpty).toList();
      final String label = segments.isEmpty ? 'root' : segments.first;

      featureBatches.putIfAbsent(
          label,
          () => {
                "openapi": spec['openapi'],
                "info": spec['info'],
                "paths": <String, dynamic>{},
                "components": {"schemas": <String, dynamic>{}}
              });
      featureBatches[label]!['paths'][pathKey] = pathData;

      final Set<String> refsFound = {};
      recursiveFindRefs(pathData, refsFound);
      for (var ref in refsFound) {
        final schemaName = ref.split('/').last;
        if (allSchemas.containsKey(schemaName)) {
          featureBatches[label]!['components']['schemas'][schemaName] =
              allSchemas[schemaName];
        }
      }
    });
    agent = OpenApiAgent(
        openApiSpec: widget.openApi,
        endpoint: widget.endpoint,
        apiKey: widget.apiKey);

    agent.addListener(() {
      setState(() {});
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            color: Colors.black45,
            child: Row(
              children: [
                Text(
                  'APIDash Agentic Testing',
                  style: TextStyle(fontSize: 16),
                ),
                Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() => agent.messages.clear()),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: agent.messages.length,
              itemBuilder: (context, i) {
                final m = agent.messages[i];
                if (i == 0 && m.role == 'system') {
                  return const SizedBox(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Hello, Start By typing Below",
                          style: TextStyle(fontSize: 21),
                        ),
                      ],
                    ),
                  );
                }
                if (m.role == 'system') {
                  print(m.role);
                  return status_system(text: m.content);
                }
                print(m);
                return Chat(message: m);
              },
            ),
          ),
          if (agent.isLoading)
            const LinearProgressIndicator(color: Colors.blue),
          input(
            contextBatching: widget.contextBatching,
            controller: _controller,
            domainKeys: featureBatches.keys.toList(),
            onDomainSelect: (key) {
              final selectedBatch = featureBatches[key]!;
              _controller.text = key;

              if (widget.contextBatching) {
                final selectedBatch = featureBatches[key]!;
                agent.updateContext(selectedBatch, isBatched: true);
              } else {
                final fullSpec = jsonDecode(widget.openApi);
                agent.updateContext(fullSpec, isBatched: false);
              }

              debugPrint("Switched context to: $key");
            },
            onSend: () {
              agent.processStep(_controller.text);
              _controller.clear();
            },
          ),
        ],
      ),
    );
  }
}

class Chat extends StatelessWidget {
  final ApiMessage message;
  const Chat({required this.message});

  @override
  Widget build(BuildContext context) {
    bool isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueGrey[800] : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: !isUser ? Border.all(color: Colors.white10) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.role.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(message.content, style: const TextStyle(fontSize: 14)),
            if (!isUser &&
                message.inputWords != null &&
                message.outputWords != null)
              Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                child: Text(
                  "Input Words: ${message.inputWords} | Output Words: ${message.outputWords}",
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class status_system extends StatelessWidget {
  final String text;
  const status_system({required this.text});

  @override
  Widget build(BuildContext context) {
    Color color = text.contains('✅')
        ? Colors.green
        : text.contains('❌') || text.contains('🛑')
            ? Colors.redAccent
            : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

class input extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  final List<String> domainKeys;
  final Function(String) onDomainSelect;
  final bool contextBatching;

  const input(
      {required this.controller,
      required this.onSend,
      required this.domainKeys,
      required this.onDomainSelect,
      required this.contextBatching});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: contextBatching
              ? Text("Context Batching Enabled ✅")
              : Text("Context Batching Disabled ❌"),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text("Available functions:"),
        ),
        SizedBox(
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: domainKeys
                  .map((key) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          onPressed: () => onDomainSelect(key),
                          child: Text(key.toUpperCase(),
                              style: TextStyle(fontSize: 10)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "Tell the agent what to do...",
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: onSend,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
