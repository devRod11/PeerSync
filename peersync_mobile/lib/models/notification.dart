class AppNotification {
  final String id;
  final String title;
  final String description;
  final String recipientID;
  final String relatedCollections;
  final String relatedDocumentID;
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.description,
    required this.recipientID,
    required this.relatedCollections,
    required this.relatedDocumentID,
    required this.type,
    required this.isRead,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['Title']?.toString() ?? 'Notification',
      description: json['description']?.toString() ?? '',
      recipientID: json['recipientID']?.toString() ?? '',
      relatedCollections:
          json['relatedCollections']?.toString() ?? '',
      relatedDocumentID:
          json['relatedDocumentID']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      isRead: json['isRead'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'Title': title,
      'description': description,
      'recipientID': recipientID,
      'relatedCollections': relatedCollections,
      'relatedDocumentID': relatedDocumentID,
      'type': type,
      'isRead': isRead,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      title: title,
      description: description,
      recipientID: recipientID,
      relatedCollections: relatedCollections,
      relatedDocumentID: relatedDocumentID,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}