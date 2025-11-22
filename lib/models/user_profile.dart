// lib/models/user_profile.dart

class UserProfile {
  final String userId;
  final String name;
  final String? imagePath; // 로컬 저장 경로
  final String? avatarUrl; // (옵션) 서버 URL

  UserProfile({
    required this.userId,
    required this.name,
    this.imagePath,
    this.avatarUrl,
  });

  // JSON 직렬화 (SharedPrefs 저장용)
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'imagePath': imagePath,
    'avatarUrl': avatarUrl,
  };

  // JSON 역직렬화
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] ?? '',
      name: json['name'] ?? 'Unknown',
      imagePath: json['imagePath'],
      avatarUrl: json['avatarUrl'],
    );
  }

  // 복사본 생성 (수정 시 사용)
  UserProfile copyWith({
    String? userId,
    String? name,
    String? imagePath,
    String? avatarUrl,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}