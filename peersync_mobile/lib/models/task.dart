class Task {
  final String id;
  final String projectID;
  final String groupID;
  final String milestoneID;
  final List<String> assignedTo;
  final String title;
  final String description;
  final DateTime dueDate;
  final String priority;
  final String status;
  final String createdBy;
  final String createdByRole;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Task({
    required this.id,
    required this.projectID,
    required this.groupID,
    required this.milestoneID,
    required this.assignedTo,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.priority,
    required this.status,
    required this.createdBy,
    required this.createdByRole,
    this.createdAt,
    this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      groupID: json['groupID']?.toString() ?? '',
      milestoneID: json['milestoneID']?.toString() ?? '',
      assignedTo: (json['assignedTo'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      dueDate: _parseDate(json['dueDate']),
      priority: json['priority']?.toString() ?? 'Medium',
      status: json['status']?.toString() ?? 'pending',
      createdBy: json['createdBy']?.toString() ?? '',
      createdByRole: json['createdByRole']?.toString() ?? '',
      createdAt: _parseOptionalDate(json['createdAt']),
      updatedAt: _parseOptionalDate(json['updatedAt']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    return _parseOptionalDate(value) ?? DateTime.now();
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    if (value is String) {
      return DateTime.tryParse(value);
    }

    // Handles Firestore timestamp objects serialized as seconds/nanoseconds.
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      final nanoseconds = value['_nanoseconds'] ?? value['nanoseconds'];

      if (seconds is num) {
        final milliseconds =
            seconds.toInt() * 1000 +
            ((nanoseconds is num ? nanoseconds.toInt() : 0) ~/ 1000000);

        return DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'projectID': projectID,
      'groupID': groupID,
      'milestoneID': milestoneID,
      'assignedTo': assignedTo,
      'title': title,
      'description': description,
      'dueDate': dueDate.toUtc().toIso8601String(),
      'priority': priority,
    };
  }
}