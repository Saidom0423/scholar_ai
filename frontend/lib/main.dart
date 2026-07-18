import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/document_viewer_screen.dart';
import 'screens/flashcard_study_screen.dart';
import 'screens/library_chat_screen.dart';

// Create ApiService provider
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final container = ProviderContainer();
  // Initialize the authentication token if already logged in
  await container.read(apiServiceProvider).initToken();
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const StudyAssistantApp(),
    ),
  );
}

class StudyAssistantApp extends ConsumerWidget {
  const StudyAssistantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiService = ref.watch(apiServiceProvider);

    final router = GoRouter(
      initialLocation: apiService.isAuthenticated ? '/dashboard' : '/login',
      redirect: (context, state) {
        final loggedIn = apiService.isAuthenticated;
        final goingToLogin = state.matchedLocation == '/login';
        
        if (!loggedIn && !goingToLogin) return '/login';
        if (loggedIn && goingToLogin) return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/document/:id',
          builder: (context, state) {
            final docId = int.parse(state.pathParameters['id']!);
            final docTitle = state.uri.queryParameters['title'] ?? 'Document';
            return DocumentViewerScreen(documentId: docId, documentTitle: docTitle);
          },
        ),
        GoRoute(
          path: '/flashcards/:id',
          builder: (context, state) {
            final setId = int.parse(state.pathParameters['id']!);
            final title = state.uri.queryParameters['title'] ?? 'Flashcards';
            return FlashcardStudyScreen(setId: setId, title: title);
          },
        ),
        GoRoute(
          path: '/library-chat',
          builder: (context, state) => const LibraryChatScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'AI Study Assistant',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Default to a gorgeous dark theme
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF), // Sleek indigo/violet primary
          brightness: Brightness.dark,
          surface: const Color(0xFF121218),
          background: const Color(0xFF0B0B0E),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
          titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, color: Colors.white),
          bodyLarge: TextStyle(fontFamily: 'Inter', color: Colors.white70),
          bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.white60),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E26),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121218),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      routerConfig: router,
    );
  }
}
