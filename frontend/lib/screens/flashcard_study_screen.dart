import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

class FlashcardStudyScreen extends ConsumerStatefulWidget {
  final int setId;
  final String title;

  const FlashcardStudyScreen({
    super.key,
    required this.setId,
    required this.title,
  });

  @override
  ConsumerState<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends ConsumerState<FlashcardStudyScreen> {
  List<Map<String, dynamic>> _flashcards = [];
  bool _isLoading = true;
  String? _error;

  int _currentIndex = 0;
  bool _showAnswer = false;

  @override
  void initState() {
    super.initState();
    _loadFlashcardSet();
  }

  Future<void> _loadFlashcardSet() async {
    try {
      final response = await ref.read(apiServiceProvider).getFlashcardSet(widget.setId);
      final cardsList = List<Map<String, dynamic>>.from(response['flashcards'] ?? []);
      if (!mounted) return;
      setState(() {
        _flashcards = cardsList;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _nextCard() {
    if (_currentIndex < _flashcards.length - 1) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showAnswer = false;
      });
    }
  }

  void _toggleReveal() {
    setState(() {
      _showAnswer = !_showAnswer;
    });
  }

  void _resetDeck() {
    setState(() {
      _currentIndex = 0;
      _showAnswer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontFamily: 'Outfit', fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text('Error loading flashcards:\n$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(onPressed: _loadFlashcardSet, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _flashcards.isEmpty
                  ? const Center(
                      child: Text('This flashcard set is empty.'),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Progress Indicators
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Card ${_currentIndex + 1} of ${_flashcards.length}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white54, fontFamily: 'Outfit'),
                              ),
                              TextButton.icon(
                                onPressed: _resetDeck,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Reset', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_currentIndex + 1) / _flashcards.length,
                            backgroundColor: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                          ),
                          const SizedBox(height: 40),
                          
                          // Flashcard Flip Canvas
                          Expanded(
                            child: GestureDetector(
                              onTap: _toggleReveal,
                              child: Card(
                                elevation: 4,
                                color: _showAnswer 
                                    ? theme.colorScheme.primary.withOpacity(0.08) 
                                    : theme.colorScheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: BorderSide(
                                    color: _showAnswer 
                                        ? theme.colorScheme.primary.withOpacity(0.4) 
                                        : Colors.white10,
                                    width: 2
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Card Role Icon Indicator
                                      Icon(
                                        _showAnswer ? Icons.lightbulb : Icons.help_outline,
                                        color: _showAnswer ? Colors.amber : theme.colorScheme.primary,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 24),
                                      
                                      // Content Text
                                      Expanded(
                                        child: Center(
                                          child: SingleChildScrollView(
                                            child: Text(
                                              _showAnswer 
                                                  ? _flashcards[_currentIndex]['answer'] ?? ''
                                                  : _flashcards[_currentIndex]['question'] ?? '',
                                              style: TextStyle(
                                                fontSize: 20, 
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Outfit',
                                                height: 1.4,
                                                color: _showAnswer ? Colors.white : Colors.white70
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 24),
                                      // Small helper text
                                      Text(
                                        _showAnswer ? 'TAP CARD TO VIEW QUESTION' : 'TAP CARD TO REVEAL ANSWER',
                                        style: const TextStyle(fontSize: 10, color: Colors.white30, letterSpacing: 1.2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          
                          // Bottom Controls Navigation
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Previous Button
                              OutlinedButton.icon(
                                onPressed: _currentIndex > 0 ? _prevCard : null,
                                icon: const Icon(Icons.chevron_left),
                                label: const Text('Back'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(120, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              
                              // Next Button
                              ElevatedButton.icon(
                                onPressed: _currentIndex < _flashcards.length - 1 
                                    ? _nextCard 
                                    : () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Deck study completed! Good job.')),
                                        );
                                        Navigator.of(context).pop();
                                      },
                                icon: Icon(_currentIndex < _flashcards.length - 1 
                                    ? Icons.chevron_right 
                                    : Icons.check_circle_outline),
                                label: Text(_currentIndex < _flashcards.length - 1 ? 'Next' : 'Finish'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(120, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
    );
  }
}
