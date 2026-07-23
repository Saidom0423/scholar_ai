import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/api_service.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  final int documentId;
  final String documentTitle;

  const DocumentViewerScreen({
    super.key,
    required this.documentId,
    required this.documentTitle,
  });

  @override
  ConsumerState<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // PDF state
  Uint8List? _pdfBytes;
  bool _loadingPdf = true;
  String? _pdfError;

  // Custom text selection menu variables
  OverlayEntry? _selectionMenuEntry;
  String? _selectedText;

  // AI Chat state
  final List<Map<String, dynamic>> _chatMessages = [];
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _sendingMessage = false;
  bool _loadingChat = true;

  // AI Summary state
  String? _summaryMarkdown;
  bool _generatingSummary = false;

  // Flashcard states
  List<Map<String, dynamic>> _flashcardSets = [];
  bool _loadingFlashcards = true;
  bool _generatingFlashcards = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPdf();
    _loadChatHistory();
    _loadFlashcardSets();
  }

  @override
  void dispose() {
    _hideHighlightOptions();
    _tabController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _showHighlightOptions(String text, Rect selectionRect, BuildContext context) {
    _hideHighlightOptions();
    
    _selectedText = text;
    
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    final menuHeight = 216.0;
    final menuWidth = 240.0;
    
    double left = selectionRect.left + (selectionRect.width - menuWidth) / 2;
    if (left < 10) left = 10;
    if (left + menuWidth > size.width - 10) {
      left = size.width - menuWidth - 10;
    }
    
    double top = selectionRect.top - menuHeight - 10;
    if (top < 50) {
      top = selectionRect.bottom + 10;
    }

    _selectionMenuEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: menuHeight,
              width: menuWidth,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E26).withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _customMenuItem(
                    emoji: '📖',
                    label: 'Explain',
                    onTap: () {
                      _hideHighlightOptions();
                      _runTextAction('explain');
                    },
                  ),
                  _customMenuItem(
                    emoji: '📝',
                    label: 'Summarize',
                    onTap: () {
                      _hideHighlightOptions();
                      _runTextAction('summarize');
                    },
                  ),
                  _customMenuItem(
                    emoji: '🎴',
                    label: 'Generate Flashcards',
                    onTap: () {
                      _hideHighlightOptions();
                      _runTextAction('generate_flashcards');
                    },
                  ),
                  _customMenuItem(
                    emoji: '❓',
                    label: 'Generate Quiz',
                    onTap: () {
                      _hideHighlightOptions();
                      _runTextAction('generate_quiz');
                    },
                  ),
                  _customMenuItem(
                    emoji: '🌐',
                    label: 'Translate',
                    onTap: () {
                      _hideHighlightOptions();
                      _runTextAction('translate');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_selectionMenuEntry!);
  }

  Widget _customMenuItem({
    required String emoji,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withOpacity(0.08),
          splashColor: Colors.white.withOpacity(0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  emoji,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: Colors.white30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideHighlightOptions() {
    if (_selectionMenuEntry != null) {
      _selectionMenuEntry!.remove();
      _selectionMenuEntry = null;
    }
  }

  Future<void> _runTextAction(String action) async {
    final text = _selectedText;
    if (text == null || text.trim().isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121218),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _TextActionSheet(
          docId: widget.documentId,
          text: text,
          action: action,
          apiService: ref.read(apiServiceProvider),
        );
      },
    );
  }

  // --- API Actions ---

  Future<void> _loadPdf() async {
    try {
      final bytes = await ref.read(apiServiceProvider).downloadDocumentBytes(widget.documentId);
      if (!mounted) return;
      setState(() {
        _pdfBytes = Uint8List.fromList(bytes);
        _loadingPdf = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfError = e.toString();
        _loadingPdf = false;
      });
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final history = await ref.read(apiServiceProvider).getChatHistory(widget.documentId);
      if (!mounted) return;
      setState(() {
        _chatMessages.clear();
        _chatMessages.addAll(history);
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

  Future<void> _loadFlashcardSets() async {
    try {
      final sets = await ref.read(apiServiceProvider).getFlashcardSets(widget.documentId);
      if (!mounted) return;
      setState(() {
        _flashcardSets = sets;
        _loadingFlashcards = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFlashcards = false;
      });
    }
  }

  Future<void> _sendChatMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() {
      _chatMessages.add({"sender": "user", "text": text, "timestamp": DateTime.now().toIso8601String()});
      _sendingMessage = true;
    });
    _scrollToBottom();

    try {
      final aiResponse = await ref.read(apiServiceProvider).sendMessage(widget.documentId, text);
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
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  Future<void> _generateSummary() async {
    setState(() {
      _generatingSummary = true;
    });
    try {
      final summary = await ref.read(apiServiceProvider).getSummary(widget.documentId);
      if (!mounted) return;
      setState(() {
        _summaryMarkdown = summary;
        _generatingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generatingSummary = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate summary: $e')),
        );
      }
    }
  }

  Future<void> _generateFlashcardSet() async {
    setState(() {
      _generatingFlashcards = true;
    });
    try {
      await ref.read(apiServiceProvider).generateFlashcards(widget.documentId);
      await _loadFlashcardSets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flashcard deck generated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate flashcards: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingFlashcards = false;
        });
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

  // --- UI Elements ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    Widget pdfPanel() {
      if (_loadingPdf) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_pdfError != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Error loading PDF:\n$_pdfError', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadPdf, child: const Text('Retry')),
            ],
          ),
        );
      }
      return SfPdfViewer.memory(
        _pdfBytes!,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        canShowTextSelectionMenu: false,
        onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
          if (details.selectedText != null && details.selectedText!.trim().isNotEmpty && details.globalSelectedRegion != null) {
            _showHighlightOptions(details.selectedText!, details.globalSelectedRegion!, context);
          } else {
            _hideHighlightOptions();
          }
        },
      );
    }

    Widget chatTab() {
      return Column(
        children: [
          Expanded(
            child: _loadingChat
                ? const Center(child: CircularProgressIndicator())
                : _chatMessages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            const Text('Ask any questions about this PDF', style: TextStyle(color: Colors.white38)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _chatMessages.length + (_sendingMessage ? 1 : 0),
                        itemBuilder: (context, idx) {
                          if (idx == _chatMessages.length) {
                            return const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('Assistant is typing...', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
                              ),
                            );
                          }
                          
                          final msg = _chatMessages[idx];
                          final isUser = msg['sender'] == 'user';
                          
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isUser ? theme.colorScheme.primary : theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  topRight: isUser ? Radius.zero : const Radius.circular(16),
                                  topLeft: isUser ? const Radius.circular(16) : Radius.zero,
                                ),
                              ),
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: MarkdownBody(
                                data: msg['text'] ?? '',
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: isUser ? Colors.white : Colors.white70),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask AI about this document...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _sendChatMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget summaryTab() {
      if (_generatingSummary) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Analyzing document & summarizing (takes ~10s)...', style: TextStyle(color: Colors.white38)),
            ],
          ),
        );
      }

      if (_summaryMarkdown == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.summarize_outlined, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'Generate an AI-powered study guide',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Overview, Key Concepts, and Definitions',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _generateSummary,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Summary'),
              ),
            ],
          ),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: MarkdownBody(
          data: _summaryMarkdown!,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            h1: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white, height: 1.6),
            h2: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white70, height: 1.5),
            p: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: Colors.white60, height: 1.4),
            listBullet: const TextStyle(color: Colors.white38),
          ),
        ),
      );
    }

    Widget flashcardsTab() {
      if (_generatingFlashcards) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating study cards (takes ~10s)...', style: TextStyle(color: Colors.white38)),
            ],
          ),
        );
      }

      if (_loadingFlashcards) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_flashcardSets.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'No flashcards generated yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Let AI create interactive quiz cards to test yourself',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _generateFlashcardSet,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Flashcards'),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _flashcardSets.length,
        itemBuilder: (context, idx) {
          final set = _flashcardSets[idx];
          final setId = set['id'] as int;
          final title = set['title'] as String;

          return Card(
            child: ListTile(
              leading: Icon(Icons.style_outlined, color: theme.colorScheme.primary),
              title: Text(
                title,
                style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Ready for study'),
              trailing: ElevatedButton(
                onPressed: () {
                  context.push('/flashcards/$setId?title=${Uri.encodeComponent(title)}');
                },
                child: const Text('Study'),
              ),
            ),
          );
        },
      );
    }

    Widget studyPanel() {
      return Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: Colors.white38,
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'AI Chat'),
              Tab(icon: Icon(Icons.summarize_outlined), text: 'Summary'),
              Tab(icon: Icon(Icons.style_outlined), text: 'Cards'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                chatTab(),
                summaryTab(),
                flashcardsTab(),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentTitle, style: const TextStyle(fontFamily: 'Outfit', fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: isWide
          ? Row(
              children: [
                // Left Panel: PDF Viewer
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.white10)),
                    ),
                    child: pdfPanel(),
                  ),
                ),
                // Right Panel: AI Study Tools
                Expanded(
                  flex: 2,
                  child: studyPanel(),
                ),
              ],
            )
          : studyPanel(), // Toggle via Bottom Sheet or tab in mobile (simplified for tab bar view here)
    );
  }
}

class _TextActionSheet extends StatefulWidget {
  final int docId;
  final String text;
  final String action;
  final ApiService apiService;

  const _TextActionSheet({
    required this.docId,
    required this.text,
    required this.action,
    required this.apiService,
  });

  @override
  State<_TextActionSheet> createState() => _TextActionSheetState();
}

class _TextActionSheetState extends State<_TextActionSheet> {
  bool _loading = true;
  String? _error;
  String? _textContent;
  
  List<Map<String, dynamic>> _flashcards = [];
  bool _showAnswer = false;
  int _currentCardIdx = 0;
  bool _savingFlashcards = false;

  List<Map<String, dynamic>> _quizQuestions = [];
  int _currentQuizIdx = 0;
  String? _selectedQuizAnswer;
  bool _quizSubmitted = false;
  int _quizScore = 0;

  String _targetLanguage = "Spanish";
  final List<String> _languages = [
    "Spanish",
    "French",
    "German",
    "Chinese",
    "Hindi",
    "Arabic",
    "Japanese",
    "Portuguese",
    "Russian",
    "Italian",
    "English"
  ];

  @override
  void initState() {
    super.initState();
    _fetchResult();
  }

  Future<void> _fetchResult() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.apiService.performTextAction(
        widget.text,
        widget.action,
        targetLanguage: _targetLanguage,
      );

      final result = response["result"] as String;

      if (widget.action == "generate_flashcards") {
        final cleanedJson = _cleanJsonString(result);
        final decoded = json.decode(cleanedJson);
        if (decoded is List) {
          _flashcards = List<Map<String, dynamic>>.from(
            decoded.map((x) => Map<String, dynamic>.from(x))
          );
        } else {
          throw Exception("Invalid flashcard list format");
        }
      } else if (widget.action == "generate_quiz") {
        final cleanedJson = _cleanJsonString(result);
        final decoded = json.decode(cleanedJson);
        if (decoded is List) {
          _quizQuestions = List<Map<String, dynamic>>.from(
            decoded.map((x) => Map<String, dynamic>.from(x))
          );
        } else {
          throw Exception("Invalid quiz format");
        }
      } else {
        _textContent = result;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _cleanJsonString(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith("```json")) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith("```")) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith("```")) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  String _getTitle() {
    switch (widget.action) {
      case 'explain':
        return 'AI Explanation';
      case 'summarize':
        return 'AI Summary';
      case 'generate_flashcards':
        return 'AI Flashcards';
      case 'generate_quiz':
        return 'Practice Quiz';
      case 'translate':
        return 'AI Translate';
      default:
        return 'AI Action';
    }
  }

  void _copyToClipboard() {
    final textToCopy = _textContent ?? widget.text;
    Clipboard.setData(ClipboardData(text: textToCopy)).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard!')),
        );
      }
    });
  }

  Future<void> _saveFlashcards() async {
    if (_flashcards.isEmpty) return;
    
    final titleController = TextEditingController(
      text: "Concepts from Selection",
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E26),
          title: const Text('Save Flashcards Deck'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Deck Title',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _savingFlashcards = true;
    });

    try {
      final formattedCards = _flashcards.map((c) => {
        "question": c["question"]?.toString() ?? "",
        "answer": c["answer"]?.toString() ?? ""
      }).toList();

      await widget.apiService.saveFlashcardBatch(
        widget.docId,
        titleController.text.trim(),
        formattedCards,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flashcard deck saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save flashcards: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingFlashcards = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        bottom: media.viewInsets.bottom,
      ),
      height: media.size.height * 0.65,
      child: Column(
        children: [
          // Drag handle and Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getTitle(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    if (widget.action == 'explain' || widget.action == 'summarize' || widget.action == 'translate')
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20, color: Colors.white70),
                        onPressed: _copyToClipboard,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Main Body
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'AI is processing text...',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchResult,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (widget.action == 'translate') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Translate to:', style: TextStyle(color: Colors.white54)),
                DropdownButton<String>(
                  value: _targetLanguage,
                  dropdownColor: const Color(0xFF1E1E26),
                  items: _languages.map((String lang) {
                    return DropdownMenuItem<String>(
                      value: lang,
                      child: Text(lang, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _targetLanguage = val;
                      });
                      _fetchResult();
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: MarkdownBody(
                data: _textContent ?? '',
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.action == 'explain' || widget.action == 'summarize') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: _textContent ?? '',
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(fontSize: 16, height: 1.5, color: Colors.white70),
            h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            listBullet: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    if (widget.action == 'generate_flashcards') {
      if (_flashcards.isEmpty) {
        return const Center(child: Text('No flashcards generated.', style: TextStyle(color: Colors.white54)));
      }
      
      final currentCard = _flashcards[_currentCardIdx];

      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showAnswer = !_showAnswer;
                    });
                  },
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _showAnswer ? const Color(0xFF2C1B4D) : const Color(0xFF1E1E26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      _showAnswer 
                          ? currentCard['answer'] ?? '' 
                          : currentCard['question'] ?? '',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _showAnswer ? const Color(0xFFB39DFF) : Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showAnswer ? 'Answer (Tap to view question)' : 'Question (Tap to view answer)',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _currentCardIdx > 0
                      ? () {
                          setState(() {
                            _currentCardIdx--;
                            _showAnswer = false;
                          });
                        }
                      : null,
                  child: const Text('Back'),
                ),
                Text(
                  'Card ${_currentCardIdx + 1} of ${_flashcards.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
                ElevatedButton(
                  onPressed: _currentCardIdx < _flashcards.length - 1
                      ? () {
                          setState(() {
                            _currentCardIdx++;
                            _showAnswer = false;
                          });
                        }
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _savingFlashcards 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_alt),
                label: const Text('Save to Flashcard Deck'),
                onPressed: _savingFlashcards ? null : _saveFlashcards,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.action == 'generate_quiz') {
      if (_quizQuestions.isEmpty) {
        return const Center(child: Text('No quiz questions generated.', style: TextStyle(color: Colors.white54)));
      }

      final isCompleted = _currentQuizIdx >= _quizQuestions.length;

      if (isCompleted) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.stars, size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              const Text(
                'Quiz Completed!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Score: $_quizScore / ${_quizQuestions.length}',
                style: const TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                _quizScore == _quizQuestions.length
                    ? 'Perfect! You have mastered this content.'
                    : _quizScore >= _quizQuestions.length / 2
                        ? 'Great effort! Review the notes to get 100%.'
                        : 'Review the text snippet and try again.',
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentQuizIdx = 0;
                    _quizScore = 0;
                    _quizSubmitted = false;
                    _selectedQuizAnswer = null;
                  });
                },
                child: const Text('Restart Quiz'),
              ),
            ],
          ),
        );
      }

      final currentQuestion = _quizQuestions[_currentQuizIdx];
      final List<String> options = List<String>.from(currentQuestion['options'] ?? []);
      final String correctAnswer = currentQuestion['correct_answer']?.toString() ?? '';

      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Question ${_currentQuizIdx + 1} of ${_quizQuestions.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(
              currentQuestion['question'] ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, idx) {
                  final opt = options[idx];
                  
                  Color buttonColor = const Color(0xFF1E1E26);
                  Color textColor = Colors.white70;
                  BorderSide borderSide = const BorderSide(color: Colors.white12);
                  
                  if (_quizSubmitted) {
                    if (opt == correctAnswer) {
                      buttonColor = Colors.green.withOpacity(0.2);
                      textColor = Colors.greenAccent;
                      borderSide = const BorderSide(color: Colors.green);
                    } else if (opt == _selectedQuizAnswer) {
                      buttonColor = Colors.red.withOpacity(0.2);
                      textColor = Colors.redAccent;
                      borderSide = const BorderSide(color: Colors.red);
                    } else {
                      textColor = Colors.white30;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: buttonColor,
                        side: borderSide,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: _quizSubmitted
                          ? null
                          : () {
                              setState(() {
                                _selectedQuizAnswer = opt;
                                _quizSubmitted = true;
                                if (opt == correctAnswer) {
                                  _quizScore++;
                                }
                              });
                            },
                      child: Text(
                        opt,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_quizSubmitted)
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentQuizIdx++;
                    _quizSubmitted = false;
                    _selectedQuizAnswer = null;
                  });
                },
                child: Text(_currentQuizIdx == _quizQuestions.length - 1 ? 'Finish Quiz' : 'Next Question'),
              ),
          ],
        ),
      );
    }

    return const SizedBox();
  }
}
