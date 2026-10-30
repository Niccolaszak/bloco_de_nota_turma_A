// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bloco_de_nota_turma_a/models/note.dart';

void main() {
  test('converte uma nota entre objeto e mapa do SQLite', () {
    final note = Note(
      id: 7,
      uid: 'user-123',
      title: 'Nota de teste',
      content: 'Conteúdo da nota',
      date: '30/10/2026 12:00',
      category: 'Estudos',
      isArchived: true,
      createdAt: DateTime.parse('2026-10-30T12:00:00.000'),
      updatedAt: DateTime.parse('2026-10-30T12:30:00.000'),
      firestoreId: 'firestore-note-7',
      needsSync: true,
    );

    final restored = Note.fromMap(note.toMap());

    expect(restored.id, note.id);
    expect(restored.uid, note.uid);
    expect(restored.title, note.title);
    expect(restored.content, note.content);
    expect(restored.category, note.category);
    expect(restored.isArchived, note.isArchived);
    expect(restored.createdAt, note.createdAt);
    expect(restored.updatedAt, note.updatedAt);
    expect(restored.firestoreId, note.firestoreId);
    expect(restored.needsSync, note.needsSync);
  });
}
