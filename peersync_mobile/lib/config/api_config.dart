class ApiConfig {
  // Android Emulator connects to the computer's localhost
  // through 10.0.2.2.
  static const String baseUrl = 'http://10.0.2.2:8000';

  static const String authMe = '$baseUrl/auth/me';
  static const String studentCheck = '$baseUrl/auth/student-check';
  static const String professorCheck = '$baseUrl/auth/professor-check';
  
  static const String projects = '$baseUrl/projects/';
  static const String groups = '$baseUrl/groups/';
  static const String milestones = '$baseUrl/milestones/';
  static const String tasks = '$baseUrl/tasks/';
  static const String submissions = '$baseUrl/submissions/';
  static const String announcements = '$baseUrl/announcements/';
  static const String notifications = '$baseUrl/notifications/';


}
