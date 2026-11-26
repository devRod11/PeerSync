import '../../services/api_service.dart';

/// Converts thrown objects into short, human-readable messages.
///
/// Raw exception strings (stack traces, HTTP bodies, Dart `Exception:`
/// prefixes) are never shown to users. Backend `detail` messages that are
/// already user-facing are preserved; everything else falls back to a
/// generic, actionable sentence.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case 400:
        return error.message.trim().isEmpty
            ? 'That request could not be completed. Check the details and try again.'
            : error.message;
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'The requested item could not be found. It may have been removed.';
      case 409:
        return error.message.trim().isEmpty
            ? 'This action conflicts with the current state. Refresh and try again.'
            : error.message;
      case 422:
        return error.message.trim().isEmpty
            ? 'Some information is invalid. Review the form and try again.'
            : error.message;
      case 503:
        return 'PeerSync is temporarily unavailable. Please try again shortly.';
      default:
        if (error.statusCode >= 500) {
          return 'The server could not complete the request. Please try again.';
        }
        return error.message.trim().isEmpty
            ? 'Something went wrong. Please try again.'
            : error.message;
    }
  }

  final text = error.toString().replaceFirst('Exception: ', '').trim();

  if (text.isEmpty || text.startsWith('Instance of')) {
    return 'Something went wrong. Please try again.';
  }

  // Network / socket failures surface as long technical strings.
  final lower = text.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('timeout')) {
    return 'Unable to reach PeerSync. Check your internet connection and try again.';
  }

  return text;
}
