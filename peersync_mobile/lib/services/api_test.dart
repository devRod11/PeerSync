
import 'package:flutter/foundation.dart';

import 'api_service.dart';

class ApiTest {
  static Future<void> testConnection() async {
    try {
      final result = await ApiService.getCurrentUser();

      debugPrint('FASTAPI CONNECTION SUCCESSFUL');
      debugPrint('Authenticated: ${result['authenticated']}');
      debugPrint('User: ${result['user']}');
    } catch (error) {
      debugPrint('FASTAPI CONNECTION FAILED');
      debugPrint(error.toString());
    }
  }
}

