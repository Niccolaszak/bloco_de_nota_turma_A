class Note {
  final int? id;
  final String uid;
  final String title;
  final String content;
  final String date;
  final String category;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? firestoreId;
  final bool needsSync;

  Note({
    this.id,
    required this.uid,
    required this.title,
    required this.content,
    required this.date,
    this.category = 'Geral',
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
    this.firestoreId,
    this.needsSync = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'title': title,
      'content': content,
      'date': date,
      'category': category,
      'isArchived': isArchived ? 1 : 0,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'firestoreId': firestoreId,
      'needsSync': needsSync ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      uid: map['uid'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      date: map['date'] as String,
      category: map['category'] as String? ?? 'Geral',
      isArchived: (map['isArchived'] as int? ?? 0) == 1,
      createdAt: map['createdAt'] == null
          ? null
          : DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String),
      firestoreId: map['firestoreId'] as String?,
      needsSync: (map['needsSync'] as int? ?? 0) == 1,
    );
  }

  Note copyWith({
    String? firestoreId,
    bool? needsSync,
    bool? isArchived,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      uid: uid,
      title: title,
      content: content,
      date: date,
      category: category,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firestoreId: firestoreId ?? this.firestoreId,
      needsSync: needsSync ?? this.needsSync,
    );
  }
}
