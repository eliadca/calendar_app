import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_calendar.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Crear tabla de eventos
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        isReminder INTEGER NOT NULL DEFAULT 0,
        reminderTime TEXT,
        hours REAL DEFAULT 0.0,
        category TEXT NOT NULL DEFAULT 'Otros',
        note TEXT,
        recurrence TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_events_date ON events(date)');
    await db.execute('CREATE INDEX idx_events_category ON events(category)');

    // Crear tabla de notas
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        isHandwritten INTEGER NOT NULL DEFAULT 0,
        tags TEXT DEFAULT '[]',
        audioPath TEXT,
        isFavorite INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_notes_date ON notes(date)');

    // Crear tabla de metas
    await db.execute('''
      CREATE TABLE goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        hours REAL NOT NULL DEFAULT 600.0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Lógica para migraciones futuras
  }

  // ***** Métodos para eventos *****
  Future<int> insertEvent(Map<String, dynamic> event) async {
    final db = await database;
    return await db.insert('events', event);
  }

  Future<List<Map<String, dynamic>>> getEventsByDate(String date) async {
    final db = await database;
    // Utilizamos 'LIKE' para filtrar por la parte inicial del campo date
    return await db.query(
      'events',
      where: 'date LIKE ?',
      whereArgs: ['$date%'],
    );
  }

  Future<List<Map<String, dynamic>>> getEventsByPeriod(DateTime start, DateTime end) async {
    final db = await database;
    // Se filtra entre start.toIso8601String() y end.toIso8601String()
    return await db.query(
      'events',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
  }

  Future<List<Map<String, dynamic>>> getEventsByMonth(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    return await db.query(
      'events',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
  }

  Future<int> updateEvent(Map<String, dynamic> event) async {
    final db = await database;
    return await db.update(
      'events',
      event,
      where: 'id = ?',
      whereArgs: [event['id']],
    );
  }

  Future<int> deleteEvent(int id) async {
    final db = await database;
    return await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getMonthlyHours(DateTime date) async {
    final db = await database;
    final startOfMonth = DateTime(date.year, date.month, 1);
    final endOfMonth = DateTime(date.year, date.month + 1, 0);
    final result = await db.rawQuery(
      'SELECT SUM(hours) as total FROM events WHERE date >= ? AND date <= ?',
      [startOfMonth.toIso8601String(), endOfMonth.toIso8601String()],
    );
    // Si no hay registros, devolvemos 0.0
    return result.first['total'] as double? ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getYearlyHours(int year) async {
    final db = await database;
    // strftime con '%Y' obtiene el año desde la columna date
    return await db.rawQuery(
      '''
      SELECT strftime("%m", date) as month, SUM(hours) as total
      FROM events
      WHERE strftime("%Y", date) = ?
      GROUP BY strftime("%m", date)
      ''',
      [year.toString()],
    );
  }

  // ***** Métodos para notas *****
  Future<int> insertNote(Map<String, dynamic> note) async {
    final db = await database;
    return await db.insert('notes', note);
  }

  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await database;
    return await db.query('notes', orderBy: 'date DESC');
  }

  Future<int> updateNote(Map<String, dynamic> note) async {
    final db = await database;
    return await db.update(
      'notes',
      note,
      where: 'id = ?',
      whereArgs: [note['id']],
    );
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ***** Métodos para metas (goals) *****
  Future<void> setGoal(int year, double hours) async {
    final db = await database;
    // REPLACE para sobrescribir la meta si ya existe
    await db.insert(
      'goals',
      {'year': year, 'hours': hours},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getGoal(int year) async {
    final db = await database;
    final result = await db.query(
      'goals',
      where: 'year = ?',
      whereArgs: [year],
    );
    // Si no existe, devolvemos 600.0 como valor por defecto
    return result.isNotEmpty ? result.first['hours'] as double : 600.0;
  }

  // ***** Métodos de respaldo y restauración *****
  Future<void> backupDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbFile = File(join(dbPath, 'smart_calendar.db'));
    final backupDir = await getTemporaryDirectory();
    final backupFile = File(
      join(backupDir.path, 'smart_calendar_backup_${DateTime.now().millisecondsSinceEpoch}.db'),
    );
    // Copiamos la base de datos actual en un archivo temporal
    await dbFile.copy(backupFile.path);
    // Compartimos el archivo .db usando share_plus
    await Share.shareXFiles(
      [XFile(backupFile.path)],
      text: 'Respaldo de Smart Calendar',
    );
  }

  Future<void> restoreDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result != null && result.files.single.path != null) {
      final backupFile = File(result.files.single.path!);
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'smart_calendar.db'));

      // Cerramos la conexión actual antes de sobreescribir la base de datos
      await _database?.close();
      await backupFile.copy(dbFile.path);

      // Forzamos la reapertura de la base de datos
      _database = null;
      await database;
    }
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('events');
    await db.delete('notes');
    await db.delete('goals');
  }
}
