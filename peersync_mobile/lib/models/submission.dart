class Submission {
  final String id;
  final String projectID;
  final String groupID;
  final String taskID;
  final String submittedBy;
  final String fileName;
  final String fileType;
  final String? driveFileId;
  final String status;
  final String? feedback;
  final String? reviewedBy;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  const Submission({
    required this.id,
    required this.projectID,
    required this.groupID,
    required this.taskID,
    required this.submittedBy,
    required this.fileName,
    required this.fileType,
    this.driveFileId,
    required this.status,
    this.feedback,
    this.reviewedBy,
    this.submittedAt,
    this.reviewedAt,
  });

  factory Submission.fromJson(Map<String, dynamic> json) {
    return Submission(
      id: json['id']?.toString() ?? '',
      projectID: json['projectID']?.toString() ?? '',
      groupID: json['groupID']?.toString() ?? '',
      taskID: json['taskID']?.toString() ?? '',
      submittedBy: json['submittedBy']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      fileType: json['fileType']?.toString() ?? '',
      driveFileId: json['driveFileId']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      feedback: json['feedback']?.toString(),
      reviewedBy: json['reviewedBy']?.toString(),
      submittedAt: _parseDate(json['submittedAt']),
      reviewedAt: _parseDate(json['reviewedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    if (value is String) {
      return DateTime.tryParse(value);
    }

    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      final nanoseconds =
          value['_nanoseconds'] ?? value['nanoseconds'];

      if (seconds is num) {
        final milliseconds = seconds.toInt() * 1000 +
            ((nanoseconds is num ? nanoseconds.toInt() : 0) ~/ 1000000);

        return DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
      }
    }

    return null;
  }

  String get displayStatus {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending Review';
      case 'revision_required':
        return 'Revision Required';
      case 'approved':
        return 'Approved';
      default:
        return status;
    }
  }
}