import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../core/cache/offline_cache.dart';
import '../models/announcement.dart';
import '../models/authenticated_user.dart';
import '../models/group.dart';
import '../models/milestone.dart';
import '../models/notification.dart';
import '../models/project.dart';
import '../models/student_option.dart';
import '../models/submission.dart';
import '../models/task.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiService {
  // Request timeout
  static const Duration _timeout = Duration(seconds: 30);

  // Retrieves the Firebase ID token of the currently logged-in user.
  static Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('No authenticated user found.');
    }

    final idToken = await user.getIdToken();

    if (idToken == null || idToken.isEmpty) {
      throw Exception('Unable to retrieve Firebase ID token.');
    }

    return idToken;
  }

  // Generates headers for authenticated API requests.
  static Future<Map<String, String>> _getHeaders() async {
    final idToken = await _getIdToken();

    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // Converts API responses into Dart objects.
  static dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;

    dynamic responseBody;

    if (response.body.isNotEmpty) {
      try {
        responseBody = jsonDecode(response.body);
      } catch (_) {
        responseBody = response.body;
      }
    }

    if (statusCode >= 200 && statusCode < 300) {
      return responseBody;
    }

    String message = 'API request failed.';

    if (responseBody is Map<String, dynamic>) {
      message =
          responseBody['detail']?.toString() ??
          responseBody['message']?.toString() ??
          message;
    } else if (responseBody is String && responseBody.isNotEmpty) {
      message = responseBody;
    }

    if (statusCode == 401) {
      message = 'Authentication failed. Please log in again.';
    } else if (statusCode == 403) {
      message = 'You do not have permission to perform this action.';
    } else if (statusCode == 404) {
      message = 'The requested resource was not found.';
    }

    throw ApiException(statusCode, message);
  }

  /// Emits `true` while the app is showing cached data because the network is
  /// unreachable, and `false` again after the next successful request.
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// Path segments whose GET responses are cached for [OfflineCache.ttl].
  static const Set<String> _cacheableSegments = {
    'auth',
    'projects',
    'groups',
    'milestones',
    'tasks',
    'submissions',
    'announcements',
    'notifications',
  };

  static bool _isCacheable(Uri uri) =>
      uri.pathSegments.isNotEmpty &&
      _cacheableSegments.contains(uri.pathSegments.first);

  /// A stable cache key for a request: path plus sorted query parameters.
  static String _cacheKey(Uri uri) {
    final query = Map<String, String>.from(uri.queryParameters);
    final keys = query.keys.toList()..sort();
    final suffix = keys.map((key) => '$key=${query[key]}').join('&');

    return suffix.isEmpty ? uri.path : '${uri.path}?$suffix';
  }

  static Future<dynamic> _readCache(String cacheKey, String? userId) async {
    final entry = await OfflineCache.read(cacheKey, userId: userId);

    if (entry == null) return null;

    offline.value = true;
    return entry.data;
  }

  // Executes an authenticated HTTP request.
  //
  // GET requests are network-first: a successful response refreshes the
  // three-day offline cache, and a network failure falls back to the cached
  // copy so the Professor and Student screens still render without a
  // connection. Mutating verbs are never cached.
  static Future<dynamic> _request(
    String method,
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool cache = true,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: queryParameters);

    final isGet = method.toUpperCase() == 'GET';
    final useCache = cache && isGet && _isCacheable(uri);
    final cacheKey = _cacheKey(uri);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    try {
      final headers = await _getHeaders();

      final encodedBody = body != null ? jsonEncode(body) : null;

      late http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(_timeout);
          break;

        case 'POST':
          response = await http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
          break;

        case 'PUT':
          response = await http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
          break;

        case 'PATCH':
          response = await http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
          break;

        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(_timeout);
          break;

        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      final decoded = _handleResponse(response);

      if (useCache) {
        unawaited(OfflineCache.write(cacheKey, decoded, userId: userId));
      }

      offline.value = false;

      return decoded;
    } on ApiException {
      // A real HTTP error (401/403/404/...) must reach the caller unchanged:
      // falling back to stale data here would hide permission failures.
      rethrow;
    } on TimeoutException {
      final cached = useCache ? await _readCache(cacheKey, userId) : null;

      if (cached != null) return cached;

      throw Exception('The server took too long to respond. Please try again.');
    } catch (error) {
      final cached = useCache ? await _readCache(cacheKey, userId) : null;

      if (cached != null) return cached;

      if (error is http.ClientException) {
        throw Exception(
          'Unable to connect to the server. Check your connection and backend.',
        );
      }

      rethrow;
    }
  }

  // Reusable GET request.
  //
  // Pass `cache: false` for a request that must never be served from the
  // offline store (for example a manual "Refresh" that should surface errors).
  static Future<dynamic> get(
    String url, {
    Map<String, String>? queryParameters,
    bool cache = true,
  }) async {
    return _request(
      'GET',
      url,
      queryParameters: queryParameters,
      cache: cache,
    );
  }

  // Reusable POST request.
  static Future<dynamic> post(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    return _request('POST', url, body: body);
  }

  // Reusable PUT request.
  static Future<dynamic> put(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    return _request('PUT', url, body: body);
  }

  // Reusable PATCH request.
  static Future<dynamic> patch(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    return _request('PATCH', url, body: body);
  }

  // Reusable DELETE request.
  static Future<dynamic> delete(String url) async {
    return _request('DELETE', url);
  }

  // Retrieves the currently authenticated user from FastAPI.
  static Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await get(ApiConfig.authMe);

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid authenticated user response.');
    }

    return response;
  }

  // Tests Professor authorization.
  static Future<Map<String, dynamic>> checkProfessorAccess() async {
    final response = await get(ApiConfig.professorCheck);

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid Professor authorization response.');
    }

    return response;
  }

  // Tests Student authorization.
  static Future<Map<String, dynamic>> checkStudentAccess() async {
    final response = await get(ApiConfig.studentCheck);

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid Student authorization response.');
    }

    return response;
  }

  // Retrieves the authenticated user as an application model.
  static Future<AuthenticatedUser> getAuthenticatedUser() async {
    final response = await getCurrentUser();

    if (response['authenticated'] != true) {
      throw Exception('User authentication could not be verified.');
    }

    final userData = response['user'];

    if (userData is! Map<String, dynamic>) {
      throw Exception('Invalid user profile response.');
    }

    return AuthenticatedUser.fromJson(userData);
  }


  // Retrieve all groups accessible to the authenticated user.
  static Future<List<Group>> getGroups() async {
    final response = await get(ApiConfig.groups);

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid groups response.');
    }

    final groupsData = response['groups'];

    if (groupsData is! List) {
      throw Exception('Invalid groups list.');
    }

    return groupsData
        .whereType<Map<String, dynamic>>()
        .map((json) => Group.fromJson(json))
        .toList();
  }

  static Future<List<StudentOption>> getAvailableStudents({ required String projectID,}) async {
    final response = await get(
      '${ApiConfig.groups}available-students',
      queryParameters: {
        'projectID': projectID,
      },
    );

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid available students response.');
    }

    final studentsData = response['students'];

    if (studentsData is! List) {
      throw Exception('Invalid students list.');
    }

    return studentsData.map((item) {
      if (item is! Map) {
        throw Exception('Invalid student record.');
      }

      return StudentOption.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
  }

  // Retrieve one group and its members.
  static Future<Group> getGroup(String groupId) async {
    final response = await get('${ApiConfig.groups}$groupId');

    if (response is! Map<String, dynamic> ||
        response['group'] is! Map<String, dynamic>) {
      throw Exception('Invalid group response.');
    }

    return Group.fromJson(
      response['group'] as Map<String, dynamic>,
    );
  }

  // Create a group.
  static Future<Group> createGroup({
    required String projectID,
    required String groupName,
    List<String> memberIDs = const [],
    String? leaderID,
  }) async {
    final response = await post(
      ApiConfig.groups,
      body: {
        'projectID': projectID,
        'groupName': groupName,
        'memberIDs': memberIDs,
        'leaderID': leaderID,
      },
    );

    if (response is! Map<String, dynamic> ||
        response['group'] is! Map<String, dynamic>) {
      throw Exception('Invalid group creation response.');
    }

    return Group.fromJson(
      response['group'] as Map<String, dynamic>,
    );
  }

  // Update a group's name.
  static Future<Group> updateGroup({
    required String groupId,
    required String groupName,
  }) async {
    final response = await put(
      '${ApiConfig.groups}$groupId',
      body: {'groupName': groupName},
    );

    if (response is! Map<String, dynamic> ||
        response['group'] is! Map<String, dynamic>) {
      throw Exception('Invalid group update response.');
    }

    return Group.fromJson(
      response['group'] as Map<String, dynamic>,
    );
  }

  // Add students to a group.
  static Future<dynamic> addGroupMembers({
    required String groupId,
    required List<String> memberIDs,
  }) async {
    return post(
      '${ApiConfig.groups}$groupId/members',
      body: {'memberIDs': memberIDs},
    );
  }

  // Assign a Group Leader.
  static Future<dynamic> assignGroupLeader({
    required String groupId,
    required String studentID,
  }) async {
    return put(
      '${ApiConfig.groups}$groupId/leader',
      body: {'studentID': studentID},
    );
  }

  // Remove a student from a group.
  static Future<dynamic> removeGroupMember({
    required String groupId,
    required String studentID,
  }) async {
    return delete(
      '${ApiConfig.groups}$groupId/members/$studentID',
    );
  }

  // Delete a group.
  static Future<dynamic> deleteGroup(String groupId) async {
    return delete('${ApiConfig.groups}$groupId');
  }

  // Retrieve all projects accessible to the authenticated user.
  static Future<List<Project>> getProjects() async {
    final response = await get(ApiConfig.projects);

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid projects response.');
    }

    final projectData = response['projects'];

    if (projectData is! List) {
      throw Exception('Invalid project list.');
    }

    return projectData.map((item) {
      if (item is! Map) {
        throw Exception('Invalid project record.');
      }

      return Project.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  // Retrieve one project by its document ID.
  static Future<Project> getProject(String projectId) async {
    final response = await get('${ApiConfig.projects}$projectId');

    if (response is! Map<String, dynamic> || response['project'] is! Map) {
      throw Exception('Invalid project response.');
    }

    return Project.fromJson(Map<String, dynamic>.from(response['project']));
  }

  // Create a new project.
  static Future<Project> createProject({
    required String title,
    required String description,
    required String academicYear,
    String status = 'ongoing',
  }) async {
    final response = await post(
      ApiConfig.projects,
      body: {
        'title': title,
        'description': description,
        'academicYear': academicYear,
        'status': status,
      },
    );

    if (response is! Map<String, dynamic> || response['project'] is! Map) {
      throw Exception('Invalid project creation response.');
    }

    return Project.fromJson(Map<String, dynamic>.from(response['project']));
  }

  // Update an existing project.
  static Future<Project> updateProject({
    required String projectId,
    required String title,
    required String description,
    required String academicYear,
    required String status,
  }) async {
    final response = await put(
      '${ApiConfig.projects}$projectId',
      body: {
        'title': title,
        'description': description,
        'academicYear': academicYear,
        'status': status,
      },
    );

    if (response is! Map<String, dynamic> || response['project'] is! Map) {
      throw Exception('Invalid project update response.');
    }

    return Project.fromJson(Map<String, dynamic>.from(response['project']));
  }

  // Delete a project.
  static Future<void> deleteProject(String projectId) async {
    await delete('${ApiConfig.projects}$projectId');
  }

  // Retrieve milestones accessible to the authenticated user.
  // Optional filters: projectID and groupID.
  static Future<List<Milestone>> getMilestones({
    String? projectID,
    String? groupID,
  }) async {
    final queryParameters = <String, String>{};

    if (projectID != null && projectID.isNotEmpty) {
      queryParameters['projectID'] = projectID;
    }

    if (groupID != null && groupID.isNotEmpty) {
      queryParameters['groupID'] = groupID;
    }

    final response = await get(
      ApiConfig.milestones,
      queryParameters:
          queryParameters.isEmpty ? null : queryParameters,
    );

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid milestones response.');
    }

    final milestoneData = response['milestones'];

    if (milestoneData is! List) {
      throw Exception('Invalid milestone list.');
    }

    return milestoneData.map((item) {
      if (item is! Map) {
        throw Exception('Invalid milestone record.');
      }

      return Milestone.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
  }

  // Retrieve one milestone by its document ID.
  static Future<Milestone> getMilestone(String milestoneId) async {
    final response = await get(
      '${ApiConfig.milestones}$milestoneId',
    );

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid milestone response.');
    }

    return Milestone.fromJson(response);
  }

  // Create a milestone.
  static Future<Milestone> createMilestone({
    required String projectID,
    required List<String> groupID,
    required String title,
    required String description,
    required int sequence,
    required DateTime startDate,
    required DateTime dueDate,
    String status = 'pending',
  }) async {
    final milestone = Milestone(
      id: '',
      projectID: projectID,
      groupID: groupID,
      title: title,
      description: description,
      sequence: sequence,
      startDate: startDate,
      dueDate: dueDate,
      status: status,
    );

    final response = await post(
      ApiConfig.milestones,
      body: milestone.toJson(),
    );

    if (response is! Map<String, dynamic> ||
        response['milestone'] is! Map) {
      throw Exception('Invalid milestone creation response.');
    }

    return Milestone.fromJson(
      Map<String, dynamic>.from(response['milestone']),
    );
  }

  // Update an existing milestone.
  // Only supplied fields will be sent to the backend.
  static Future<Milestone> updateMilestone({
    required String milestoneId,
    List<String>? groupID,
    String? title,
    String? description,
    int? sequence,
    DateTime? startDate,
    DateTime? dueDate,
    String? status,
  }) async {
    final body = <String, dynamic>{};

    if (groupID != null) body['groupID'] = groupID;
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (sequence != null) body['sequence'] = sequence;
    if (startDate != null) {
      body['startDate'] = startDate.toUtc().toIso8601String();
    }
    if (dueDate != null) {
      body['dueDate'] = dueDate.toUtc().toIso8601String();
    }
    if (status != null) body['status'] = status;

    if (body.isEmpty) {
      throw Exception('No milestone fields were provided for update.');
    }

    final response = await put(
      '${ApiConfig.milestones}$milestoneId',
      body: body,
    );

    if (response is! Map<String, dynamic> ||
        response['milestone'] is! Map) {
      throw Exception('Invalid milestone update response.');
    }

    return Milestone.fromJson(
      Map<String, dynamic>.from(response['milestone']),
    );
  }

  // Delete a milestone.
  static Future<void> deleteMilestone(String milestoneId) async {
    await delete('${ApiConfig.milestones}$milestoneId');
  }

  // Retrieve tasks accessible to the authenticated user.
  static Future<List<Task>> getTasks({
    String? projectID,
    String? groupID,
    String? milestoneID,
  }) async {
    final queryParameters = <String, String>{};

    if (projectID != null && projectID.isNotEmpty) {
      queryParameters['projectID'] = projectID;
    }

    if (groupID != null && groupID.isNotEmpty) {
      queryParameters['groupID'] = groupID;
    }

    if (milestoneID != null && milestoneID.isNotEmpty) {
      queryParameters['milestoneID'] = milestoneID;
    }

    final response = await get(
      ApiConfig.tasks,
      queryParameters:
          queryParameters.isEmpty ? null : queryParameters,
    );

    if (response is! Map<String, dynamic> ||
        response['tasks'] is! List) {
      throw Exception('Invalid tasks response.');
    }

    return (response['tasks'] as List).map((item) {
      if (item is! Map) {
        throw Exception('Invalid task record.');
      }

      return Task.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  // Retrieve one task.
  static Future<Task> getTask(String taskId) async {
    final response = await get('${ApiConfig.tasks}$taskId');

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid task response.');
    }

    return Task.fromJson(response);
  }

  // Create a task.
  static Future<Task> createTask({
    required String projectID,
    required String groupID,
    required String milestoneID,
    required List<String> assignedTo,
    required String title,
    required String description,
    required DateTime dueDate,
    String priority = 'Medium',
  }) async {
    final response = await post(
      ApiConfig.tasks,
      body: {
        'projectID': projectID,
        'groupID': groupID,
        'milestoneID': milestoneID,
        'assignedTo': assignedTo,
        'title': title,
        'description': description,
        'dueDate': dueDate.toUtc().toIso8601String(),
        'priority': priority,
      },
    );

    if (response is! Map<String, dynamic> ||
        response['task'] is! Map) {
      throw Exception('Invalid task creation response.');
    }

    return Task.fromJson(
      Map<String, dynamic>.from(response['task']),
    );
  }

  // Update task details.
  static Future<Task> updateTask({
    required String taskId,
    List<String>? assignedTo,
    String? title,
    String? description,
    DateTime? dueDate,
    String? priority,
  }) async {
    final body = <String, dynamic>{};

    if (assignedTo != null) body['assignedTo'] = assignedTo;
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (dueDate != null) {
      body['dueDate'] = dueDate.toUtc().toIso8601String();
    }
    if (priority != null) body['priority'] = priority;

    if (body.isEmpty) {
      throw Exception('No task fields provided for update.');
    }

    final response = await put(
      '${ApiConfig.tasks}$taskId',
      body: body,
    );

    if (response is! Map<String, dynamic> ||
        response['task'] is! Map) {
      throw Exception('Invalid task update response.');
    }

    return Task.fromJson(
      Map<String, dynamic>.from(response['task']),
    );
  }

  // Delete a task.
  static Future<void> deleteTask(String taskId) async {
    await delete('${ApiConfig.tasks}$taskId');
  }

  // Create an individual student submission.
  static Future<Submission> createSubmission({
    required String projectID,
    required String groupID,
    required String taskID,
    required String fileName,
    required String fileType,
  }) async {
    final response = await post(
      ApiConfig.submissions,
      body: {
        'projectID': projectID,
        'groupID': groupID,
        'taskID': taskID,
        'fileName': fileName,
        'fileType': fileType,
      },
    );

    if (response is! Map<String, dynamic> ||
        response['submission'] is! Map) {
      throw Exception('Invalid submission creation response.');
    }

    return Submission.fromJson(
      Map<String, dynamic>.from(response['submission']),
    );
  }


  // Upload an actual submission file to the FastAPI backend.
  static Future<Submission> uploadSubmission({
    required String projectID,
    required String groupID,
    required String taskID,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    const maxUploadSize = 25 * 1024 * 1024;

    if (fileBytes.isEmpty) {
      throw Exception('The selected file is empty.');
    }

    if (fileBytes.length > maxUploadSize) {
      throw Exception('File size exceeds the 25 MB limit.');
    }

    final idToken = await _getIdToken();

    final uri = Uri.parse('${ApiConfig.submissions}upload');

    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll({
      'Authorization': 'Bearer $idToken',
      'Accept': 'application/json',
    });

    request.fields.addAll({
      'projectID': projectID,
      'groupID': groupID,
      'taskID': taskID,
    });

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    try {
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      final responseData = _handleResponse(response);

      if (responseData is! Map<String, dynamic> ||
          responseData['submission'] is! Map) {
        throw Exception('Invalid submission upload response.');
      }

      return Submission.fromJson(
        Map<String, dynamic>.from(
          responseData['submission'],
        ),
      );
    } on TimeoutException {
      throw Exception(
        'File upload timed out. Please check your connection and try again.',
      );
    }
  }


  // Retrieve submissions accessible to the authenticated user.
  // Optional filters: projectID, groupID, and taskID.
  static Future<List<Submission>> getSubmissions({
    String? projectID,
    String? groupID,
    String? taskID,
  }) async {
    final queryParameters = <String, String>{};

    if (projectID != null && projectID.isNotEmpty) {
      queryParameters['projectID'] = projectID;
    }

    if (groupID != null && groupID.isNotEmpty) {
      queryParameters['groupID'] = groupID;
    }

    if (taskID != null && taskID.isNotEmpty) {
      queryParameters['taskID'] = taskID;
    }

    final response = await get(
      ApiConfig.submissions,
      queryParameters:
          queryParameters.isEmpty ? null : queryParameters,
    );

    if (response is! Map<String, dynamic> ||
        response['submissions'] is! List) {
      throw Exception('Invalid submissions response.');
    }

    return (response['submissions'] as List).map((item) {
      if (item is! Map) {
        throw Exception('Invalid submission record.');
      }

      return Submission.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
  }

  // Review an individual student submission.
  // status must be "approved" or "revision_required".
  static Future<void> reviewSubmission({
    required String submissionId,
    required String status,
    String? feedback,
  }) async {
    final normalizedStatus = status.toLowerCase().trim();

    if (normalizedStatus != 'approved' &&
        normalizedStatus != 'revision_required') {
      throw Exception('Invalid submission review status.');
    }

    if (normalizedStatus == 'revision_required' &&
        (feedback == null || feedback.trim().isEmpty)) {
      throw Exception(
        'Feedback is required when requesting revisions.',
      );
    }

    await patch(
      '${ApiConfig.submissions}$submissionId/review',
      body: {
        'status': normalizedStatus,
        'feedback': feedback?.trim(),
      },
    );
  }

  // Delete a student's own pending submission.
  static Future<void> deleteSubmission(String submissionId) async {
    await delete('${ApiConfig.submissions}$submissionId');
  }

    // Download a submission file through the authenticated FastAPI backend.
  // The backend retrieves the actual file from Google Drive.
  static Future<http.Response> downloadSubmission({
    required String submissionId,
  }) async {
    final idToken = await _getIdToken();

    final uri = Uri.parse(
      '${ApiConfig.submissions}$submissionId/download',
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 120));

      // Reuse the existing API error handling for unsuccessful responses.
      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        _handleResponse(response);
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('The downloaded file is empty.');
      }

      return response;
    } on TimeoutException {
      throw Exception(
        'File download timed out. Please check your connection and try again.',
      );
    } on http.ClientException {
      throw Exception(
        'Unable to connect to the server. Check your connection and backend.',
      );
    }
  }


  // Retrieve announcements accessible to the authenticated user.
  // Optional filters: projectID and groupID.
  static Future<List<Announcement>> getAnnouncements({
    String? projectID,
    String? groupID,
  }) async {
    final queryParameters = <String, String>{};

    if (projectID != null && projectID.isNotEmpty) {
      queryParameters['projectID'] = projectID;
    }

    if (groupID != null && groupID.isNotEmpty) {
      queryParameters['groupID'] = groupID;
    }

    final response = await get(
      ApiConfig.announcements,
      queryParameters:
          queryParameters.isEmpty ? null : queryParameters,
    );

    if (response is! Map<String, dynamic> ||
        response['announcements'] is! List) {
      throw Exception('Invalid announcements response.');
    }

    return (response['announcements'] as List).map((item) {
      if (item is! Map) {
        throw Exception('Invalid announcement record.');
      }

      return Announcement.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
  }


  // Retrieve notifications belonging to the authenticated user.
  // Optional filter: isRead.
  static Future<List<AppNotification>> getNotifications({
    bool? isRead,
  }) async {
    final queryParameters = <String, String>{};

    if (isRead != null) {
      queryParameters['isRead'] = isRead.toString();
    }

    final response = await get(
      ApiConfig.notifications,
      queryParameters:
          queryParameters.isEmpty ? null : queryParameters,
    );

    if (response is! Map<String, dynamic> ||
        response['notifications'] is! List) {
      throw Exception('Invalid notifications response.');
    }

    return (response['notifications'] as List).map((item) {
      if (item is! Map) {
        throw Exception('Invalid notification record.');
      }

      return AppNotification.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();
  }

  // Mark an individual notification as read or unread.
  static Future<void> updateNotificationReadStatus({
    required String notificationId,
    required bool isRead,
  }) async {
    await patch(
      '${ApiConfig.notifications}$notificationId',
      body: {'isRead': isRead},
    );
  }

  // Mark all notifications belonging to the authenticated user as read.
  static Future<void> markAllNotificationsAsRead() async {
    await patch(
      '${ApiConfig.notifications}read-all',
      body: {},
    );
  }

  // Delete an individual notification belonging to the authenticated user.
  static Future<void> deleteNotification(
    String notificationId,
  ) async {
    await delete(
      '${ApiConfig.notifications}$notificationId',
    );
  }


  // Retrieve one announcement.
  static Future<Announcement> getAnnouncement(
    String announcementId,
  ) async {
    final response = await get(
      '${ApiConfig.announcements}$announcementId',
    );

    if (response is! Map<String, dynamic> ||
        response['announcement'] is! Map) {
      throw Exception('Invalid announcement response.');
    }

    return Announcement.fromJson(
      Map<String, dynamic>.from(response['announcement']),
    );
  }

  // Create an announcement.
  // targetType must be "project" or "group".
  static Future<Announcement> createAnnouncement({
    required String projectID,
    required String targetType,
    List<String>? groupID,
    required String title,
    required String content,
  }) async {
    final normalizedTarget = targetType.toLowerCase().trim();

    if (normalizedTarget != 'project' &&
        normalizedTarget != 'group') {
      throw Exception('Invalid announcement target type.');
    }

    if (normalizedTarget == 'group' &&
        (groupID == null || groupID.isEmpty)) {
      throw Exception(
        'Select at least one group for a group announcement.',
      );
    }

    final response = await post(
      ApiConfig.announcements,
      body: {
        'projectID': projectID,
        'targetType': normalizedTarget,
        'groupID':
            normalizedTarget == 'project' ? null : groupID,
        'title': title.trim(),
        'content': content.trim(),
      },
    );

    if (response is! Map<String, dynamic> ||
        response['announcement'] is! Map) {
      throw Exception('Invalid announcement creation response.');
    }

    return Announcement.fromJson(
      Map<String, dynamic>.from(response['announcement']),
    );
  }

  static Future<Announcement> updateAnnouncement({
    required String announcementId,
    String? targetType,
    List<String>? groupID,
    String? title,
    String? content,
  }) async {
    final body = <String, dynamic>{};

    if (targetType != null) {
      final normalizedTarget = targetType.toLowerCase().trim();

      if (normalizedTarget != 'project' &&
          normalizedTarget != 'group') {
        throw Exception('Invalid announcement target type.');
      }

      body['targetType'] = normalizedTarget;

      // Project-wide announcements must not have group targets.
      if (normalizedTarget == 'project') {
        body['groupID'] = null;
      } else if (groupID != null) {
        body['groupID'] = groupID;
      }
    } else if (groupID != null) {
      body['groupID'] = groupID;
    }

    if (title != null) {
      body['title'] = title.trim();
    }

    if (content != null) {
      body['content'] = content.trim();
    }

    if (body.isEmpty) {
      throw Exception(
        'No announcement fields were provided for update.',
      );
    }

    // A group-targeted announcement must have at least one group.
    if (body['targetType'] == 'group' &&
        (body['groupID'] == null ||
            (body['groupID'] as List).isEmpty)) {
      throw Exception(
        'Select at least one group for a group announcement.',
      );
    }

    final response = await put(
      '${ApiConfig.announcements}$announcementId',
      body: body,
    );

    if (response is! Map<String, dynamic> ||
        response['announcement'] is! Map) {
      throw Exception('Invalid announcement update response.');
    }

    return Announcement.fromJson(
      Map<String, dynamic>.from(response['announcement']),
    );
  }

  // Delete an announcement.
  static Future<void> deleteAnnouncement(
    String announcementId,
  ) async {
    await delete(
      '${ApiConfig.announcements}$announcementId',
    );
  }
}