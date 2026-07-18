import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Update this to your Render deployment URL when hosted in cloud
  static const String _defaultBaseUrl = "http://localhost:8000";
  
  late final Dio _dio;
  String? _token;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _defaultBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
    
    // Add request interceptor to automatically add JWT Token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_token != null) {
          options.headers["Authorization"] = "Bearer $_token";
        } else {
          final prefs = await SharedPreferences.getInstance();
          final savedToken = prefs.getString("jwt_token");
          if (savedToken != null) {
            _token = savedToken;
            options.headers["Authorization"] = "Bearer $savedToken";
          }
        }
        return handler.next(options);
      },
      onError: (e, handler) {
        // Handle token expiration / unauthorized responses
        if (e.response?.statusCode == 401) {
          logout();
        }
        return handler.next(e);
      }
    ));
  }

  bool get isAuthenticated => _token != null;

  Future<void> initToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("jwt_token");
  }

  // --- Auth API ---

  Future<bool> register(String email, String phone, String password) async {
    try {
      await _dio.post("/api/auth/register", data: {
        "email": email,
        "phone": phone.isEmpty ? null : phone,
        "password": password,
      });
      return true;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<String> login(String emailOrPhone, String password) async {
    try {
      final formData = FormData.fromMap({
        "username": emailOrPhone,  // FastAPI form expect 'username' parameter
        "password": password,
      });
      
      final response = await _dio.post("/api/auth/login", data: formData);
      final token = response.data["access_token"] as String;
      
      _token = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("jwt_token", token);
      
      return token;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("jwt_token");
  }

  // --- Documents API ---

  Future<List<Map<String, dynamic>>> getDocuments() async {
    try {
      final response = await _dio.get("/api/documents");
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> uploadDocument(PlatformFile file) async {
    try {
      MultipartFile multipartFile;
      if (file.bytes != null) {
        // Web uploads provide bytes
        multipartFile = MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
        );
      } else if (file.path != null) {
        // Mobile / Desktop uploads provide file paths
        multipartFile = await MultipartFile.fromFile(
          file.path!,
          filename: file.name,
        );
      } else {
        throw "Unsupported file resource format";
      }

      final formData = FormData.fromMap({
        "file": multipartFile,
      });

      final response = await _dio.post(
        "/api/documents/upload", 
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        )
      );
      return response.data;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> deleteDocument(int docId) async {
    try {
      await _dio.delete("/api/documents/$docId");
    } catch (e) {
      throw _parseError(e);
    }
  }

  String getDownloadUrl(int docId) {
    // Generate authenticated link or relative URL for Syncfusion viewer
    // Syncfusion requires either file path, network URL, or byte stream.
    // We will download PDF bytes using downloadDocumentBytes for viewing.
    return "${_dio.options.baseUrl}/api/documents/$docId/download";
  }

  Future<List<int>> downloadDocumentBytes(int docId) async {
    try {
      final response = await _dio.get<List<int>>(
        "/api/documents/$docId/download",
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data!;
    } catch (e) {
      throw _parseError(e);
    }
  }

  // --- Chat & Study AI API ---

  Future<Map<String, dynamic>> sendMessage(int docId, String question) async {
    try {
      final response = await _dio.post(
        "/api/documents/$docId/chat",
        data: {"question": question},
      );
      return response.data;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getChatHistory(int docId) async {
    try {
      final response = await _dio.get("/api/documents/$docId/chat-history");
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> sendLibraryMessage(String question, List<int>? docIds) async {
    try {
      final response = await _dio.post(
        "/api/library/chat",
        data: {
          "question": question,
          "document_ids": docIds,
        },
      );
      return response.data;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getLibraryChatHistory() async {
    try {
      final response = await _dio.get("/api/library/chat-history");
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<String> getSummary(int docId) async {
    try {
      final response = await _dio.post("/api/documents/$docId/summary");
      return response.data["answer"] as String;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> generateFlashcards(int docId) async {
    try {
      final response = await _dio.post("/api/documents/$docId/flashcards");
      return response.data;
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getFlashcardSets(int docId) async {
    try {
      final response = await _dio.get("/api/documents/$docId/flashcard-sets");
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> getFlashcardSet(int setId) async {
    try {
      final response = await _dio.get("/api/flashcard-sets/$setId");
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> performTextAction(String text, String action, {String targetLanguage = "Spanish"}) async {
    try {
      final response = await _dio.post(
        "/api/documents/text-action",
        data: {
          "text": text,
          "action": action,
          "target_language": targetLanguage,
        },
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> saveFlashcardBatch(int docId, String title, List<Map<String, dynamic>> cards) async {
    try {
      final response = await _dio.post(
        "/api/documents/$docId/flashcards/save-batch",
        data: {
          "title": title,
          "flashcards": cards,
        },
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      throw _parseError(e);
    }
  }

  // --- Error Parsing Helper ---

  String _parseError(dynamic e) {
    if (e is DioException) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData.containsKey("detail")) {
        return responseData["detail"].toString();
      }
      return e.message ?? "An network error occurred";
    }
    return e.toString();
  }
}
