import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';

class LibraryChatScreen extends ConsumerStatefulWidget {
  const LibraryChatScreen({super.key});

  @override
  ConsumerState<LibraryChatScreen> createState() => _LibraryChatScreenState();
}

class _LibraryChatScreenState extends ConsumerState<LibraryChatScreen> {
  // Documents filter list
  List<Map<String, dynamic>> _documents = [];
  final Set<int> _selectedDocIds = {};
  bool _loadingDocs = true;

  // Chat feed
  List<Map<String, dynamic>> _chatMessages = [];
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _sendingMessage = false;
  bool _loadingChat = true;

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDocuments() async {
    try {
      final docs = await ref.read(apiServiceProvider).getDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loadingDocs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDocs = false;
      });
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final history = await ref.read(apiServiceProvider).getLibraryChatHistory();
      if (!mounted) return;
      setState(() {
        _chatMessages = history;
        _loadingChat = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChat = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() {
      _chatMessages.add({
        "sender": "user", 
        "text": text, 
        "timestamp": DateTime.now().toIso8601String()
      });
      _sendingMessage = true;
    });
    _scrollToBottom();

    // If no document is selected, search across all documents
    final docFilter = _selectedDocIds.isEmpty ? null : _selectedDocIds.toList();

    try {
      final aiResponse = await ref.read(apiServiceProvider).sendLibraryMessage(text, docFilter);
      if (!mounted) return;
      setState(() {
        _chatMessages.add(aiResponse);
        _sendingMessage = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingMessage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleDocSelection(int docId) {
    setState(() {
      if (_selectedDocIds.contains(docId)) {
        _selectedDocIds.remove(docId);
      } else {
        _selectedDocIds.add(docId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 800;

    Widget filterSidebar() {
      return Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search Filters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDocIds.isEmpty 
                  ? 'Searching across all documents' 
                  : 'Searching ${_selectedDocIds.length} selected document(s)',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const Divider(height: 24, color: Colors.white10),
            Expanded(
              child: _loadingDocs
                  ? const Center(child: CircularProgressIndicator())
                  : _documents.isEmpty
                      ? const Center(
                          child: Text(
                            'No documents found to search.',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _documents.length,
                          itemBuilder: (context, idx) {
                            final doc = _documents[idx];
                            final id = doc['id'] as int;
                            final title = doc['title'] as String;
                            final isChecked = _selectedDocIds.contains(id);

                            return CheckboxListTile(
                              value: isChecked,
                              onChanged: (_) => _toggleDocSelection(id),
                              title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontFamily: 'Outfit'),
                              ),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: theme.colorScheme.primary,
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    }

    Widget chatView() {
      return Column(
        children: [
          Expanded(
            child: _loadingChat
                ? const Center(child: CircularProgressIndicator())
                : _chatMessages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_rounded, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              const Text(
                                'Ask your Library anything!',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'The assistant will retrieve context from all selected documents and compile a cited answer.',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: _chatMessages.length + (_sendingMessage ? 1 : 0),
                        itemBuilder: (context, idx) {
                          if (idx == _chatMessages.length) {
                            return const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('Assistant searching & compiling...', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
                              ),
                            );
                          }

                          final msg = _chatMessages[idx];
                          final isUser = msg['sender'] == 'user';

                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isUser ? theme.colorScheme.primary : theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  topRight: isUser ? Radius.zero : const Radius.circular(16),
                                  topLeft: isUser ? const Radius.circular(16) : Radius.zero,
                                ),
                              ),
                              constraints: const BoxConstraints(maxWidth: 500),
                              child: MarkdownBody(
                                data: msg['text'] ?? '',
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: isUser ? Colors.white : Colors.white70, height: 1.4),
                                  h1: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
                                  h2: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
                                  listBullet: const TextStyle(color: Colors.white38),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask library (e.g. Compare the concepts in Unit 2 and Unit 4)...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Assistant', style: TextStyle(fontFamily: 'Outfit')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: isWide
          ? Row(
              children: [
                // Left Panel: Search filters sidebar
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.white10)),
                    ),
                    child: filterSidebar(),
                  ),
                ),
                // Right Panel: Library RAG chat window
                Expanded(
                  flex: 3,
                  child: chatView(),
                ),
              ],
            )
          : chatView(), // On mobile, we default to the chat window (can add sheet for filters if needed)
      // Floating button for filtering on mobile
      floatingActionButton: !isWide
          ? FloatingActionButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => filterSidebar(),
                );
              },
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.filter_list, color: Colors.white),
            )
          : null,
    );
  }
}
