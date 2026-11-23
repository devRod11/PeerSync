class AuthenticatedUser {
  final String uid;
  final String? displayName;
  final String? email;
  final String role;
  final bool isActive;

  const AuthenticatedUser({
    required this.uid,
    this.displayName,
    this.email,
    required this.role,
    required this.isActive,
  });

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUser(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String,
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}