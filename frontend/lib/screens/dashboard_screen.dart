import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../main.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
  }

  Future<void> _fetchDocuments() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final docs = await ref.read(apiServiceProvider).getDocuments();
      setState(() {
        _documents = docs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load documents: $e')),
        );
      }
    }
  }

  Future<void> _uploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() {
      _isUploading = true;
      _statusMessage = "Uploading & AI indexing PDF (this might take a few moments)...";
    });

    try {
      await ref.read(apiServiceProvider).uploadDocument(file);
      await _fetchDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF uploaded and indexed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _deleteDoc(int docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document?'),
        content: const Text('Are you sure you want to delete this document? This will remove all AI embeddings, flashcards, and chat history associated with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(apiServiceProvider).deleteDocument(docId);
      await _fetchDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete document: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    await ref.read(apiServiceProvider).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library', style: TextStyle(fontFamily: 'Outfit')),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Library Assistant',
            onPressed: () => context.push('/library-chat'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Upload Card
                Card(
                  child: InkWell(
                    onTap: _isUploading ? null : _uploadPdf,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Upload Study Material',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Support PDF files up to 20MB',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Documents',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                ),
                const SizedBox(height: 12),
                
                // Document List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _documents.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.library_books_outlined, size: 64, color: Colors.white24),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No documents uploaded yet',
                                    style: TextStyle(fontSize: 16, color: Colors.white54, fontFamily: 'Outfit'),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: _uploadPdf,
                                    child: const Text('Upload your first PDF'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _documents.length,
                              itemBuilder: (context, idx) {
                                final doc = _documents[idx];
                                final docId = doc['id'] as int;
                                final title = doc['title'] as String;
                                final rawDate = doc['upload_date'] as String;
                                String formattedDate = '';
                                try {
                                  final parsedDate = DateTime.parse(rawDate);
                                  formattedDate = DateFormat('MMM d, yyyy').format(parsedDate);
                                } catch (_) {
                                  formattedDate = rawDate;
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                        child: Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
                                      ),
                                      title: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                      ),
                                      subtitle: Text(
                                        'Uploaded on $formattedDate',
                                        style: const TextStyle(fontSize: 12, color: Colors.white38),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                                            tooltip: 'Delete',
                                            onPressed: () => _deleteDoc(docId),
                                          ),
                                          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                                        ],
                                      ),
                                      onTap: () {
                                        context.push('/document/$docId?title=${Uri.encodeComponent(title)}');
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          
          // Uploading overlay loader
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          _statusMessage ?? 'Processing...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
