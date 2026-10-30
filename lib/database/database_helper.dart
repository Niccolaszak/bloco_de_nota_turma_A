import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    } else {
      _database = await _initDB('notes.db');

      return _database!;
    }
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
        CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uid TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          date TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Geral',
          isArchived INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT,
          updatedAt TEXT,
          firestoreId TEXT,
          needsSync INTEGER NOT NULL DEFAULT 1
        )
      ''');
    await db.execute('''
      CREATE TABLE pending_deletes(
        firestoreId TEXT PRIMARY KEY,
        userId TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE notes ADD COLUMN category TEXT NOT NULL DEFAULT 'Geral'",
      );
      await db.execute(
        'ALTER TABLE notes ADD COLUMN isArchived INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE notes ADD COLUMN createdAt TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN updatedAt TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE notes ADD COLUMN firestoreId TEXT');
      await db.execute(
        'ALTER TABLE notes ADD COLUMN needsSync INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute('''
        CREATE TABLE pending_deletes(
          firestoreId TEXT PRIMARY KEY,
          userId TEXT NOT NULL
        )
      ''');
    }
  }

  Future<int> insertNote(Note note) async {
    final db = await database;
    final collection = FirebaseFirestore.instance.collection('notes');
    final firestoreId = note.firestoreId ?? collection.doc().id;
    final localNote = note.copyWith(firestoreId: firestoreId, needsSync: true);
    final id = await db.insert('notes', localNote.toMap());
    final insertedRows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    await _tryUpload(Note.fromMap(insertedRows.first));
    return id;
  }

  Future<List<Note>> getNotes(String uid) async {
    final db = await instance.database;

    final result = await db.query(
      "notes",

      where: "uid = ?",

      whereArgs: [uid],

      orderBy: "id DESC",
    );

    return result.map((map) => Note.fromMap(map)).toList();
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    final collection = FirebaseFirestore.instance.collection('notes');
    final localNote = note.copyWith(
      firestoreId: note.firestoreId ?? collection.doc().id,
      needsSync: true,
    );
    final count = await db.update(
      'notes',
      localNote.toMap(),
      where: "id = ?",
      whereArgs: [note.id],
    );
    await _tryUpload(localNote);
    return count;
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    final note = Note.fromMap(rows.first);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final deleted = await db.transaction((txn) async {
      if (note.firestoreId != null && userId != null) {
        await txn.insert(
          'pending_deletes',
          {'firestoreId': note.firestoreId, 'userId': userId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return txn.delete('notes', where: 'id = ?', whereArgs: [id]);
    });

    if (note.firestoreId != null && userId != null) {
      await _tryDeleteRemote(note.firestoreId!, userId);
    }
    return deleted;
  }

  Future<void> _tryUpload(Note note) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId != note.uid || note.firestoreId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(note.firestoreId)
          .set({
        'title': note.title,
        'content': note.content,
        'category': note.category,
        'isArchived': note.isArchived,
        'createdAt': Timestamp.fromDate(note.createdAt ?? DateTime.now()),
        'updatedAt': Timestamp.fromDate(note.updatedAt ?? DateTime.now()),
        'userId': userId,
      });
      final db = await database;
      await db.update(
        'notes',
        {'needsSync': 0},
        where: 'id = ? AND firestoreId = ?',
        whereArgs: [note.id, note.firestoreId],
      );
    } catch (e, stackTrace) {
      debugPrint('Falha ao enviar nota ao Firestore: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _tryDeleteRemote(String firestoreId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(firestoreId)
          .delete();
      final db = await database;
      await db.delete(
        'pending_deletes',
        where: 'firestoreId = ? AND userId = ?',
        whereArgs: [firestoreId, userId],
      );
    } catch (_) {
      // A exclusão local permanece registrada para ser repetida na sincronização.
    }
  }

  Future<void> syncNotes() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final db = await database;

    try {
      final pendingDeletes = await db.query(
        'pending_deletes',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      final deletedIds = pendingDeletes
          .map((row) => row['firestoreId'] as String)
          .toSet();
      for (final deletion in pendingDeletes) {
        await _tryDeleteRemote(deletion['firestoreId'] as String, userId);
      }

      final collection = FirebaseFirestore.instance.collection('notes');
      final remote = await collection.where('userId', isEqualTo: userId).get();
      for (final document in remote.docs) {
        if (deletedIds.contains(document.id)) continue;
        final data = document.data();
        final remoteNote = _noteFromFirestore(document.id, data, userId);
        final localRows = await db.query(
          'notes',
          where: 'uid = ? AND firestoreId = ?',
          whereArgs: [userId, document.id],
          limit: 1,
        );
        if (localRows.isEmpty) {
          await db.insert('notes', remoteNote.toMap());
          continue;
        }

        final localNote = Note.fromMap(localRows.first);
        final remoteUpdated = remoteNote.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final localUpdated = localNote.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (remoteUpdated.isAfter(localUpdated)) {
          final remoteValues = remoteNote.toMap()..remove('id');
          await db.update(
            'notes',
            remoteValues,
            where: 'id = ?',
            whereArgs: [localNote.id],
          );
        }
      }

      final pendingNotes = await db.query(
        'notes',
        where: 'uid = ? AND needsSync = 1',
        whereArgs: [userId],
      );
      for (final row in pendingNotes) {
        var note = Note.fromMap(row);
        if (note.firestoreId == null) {
          note = note.copyWith(firestoreId: collection.doc().id);
          await db.update(
            'notes',
            {'firestoreId': note.firestoreId},
            where: 'id = ?',
            whereArgs: [note.id],
          );
        }
        await _tryUpload(note);
      }
    } catch (_) {
      // Falhas de rede não impedem o uso das notas armazenadas no SQLite.
    }
  }

  Note _noteFromFirestore(
    String documentId,
    Map<String, dynamic> data,
    String userId,
  ) {
    DateTime? asDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final createdAt = asDateTime(data['createdAt']);
    final updatedAt = asDateTime(data['updatedAt']);
    final displayDate = createdAt == null
        ? ''
        : '${createdAt.day.toString().padLeft(2, '0')}/'
            '${createdAt.month.toString().padLeft(2, '0')}/'
            '${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:'
            '${createdAt.minute.toString().padLeft(2, '0')}';

    return Note(
      uid: userId,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      date: displayDate,
      category: data['category'] as String? ?? 'Geral',
      isArchived: data['isArchived'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      firestoreId: documentId,
      needsSync: false,
    );
  }
}
