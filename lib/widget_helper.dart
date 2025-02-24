import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetHelper {
  static const String widgetName = 'SmartCalendarWidgetProvider';
  static const String appGroupId = 'group.com.example.calendar_app';

  /// Inicializa el widget y registra el callback en segundo plano.
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(appGroupId);
    await HomeWidget.registerBackgroundCallback(backgroundCallback);
    await updateWidgetData(); // Actualiza los datos al iniciar
  }

  /// Callback que se ejecuta cuando se recibe una acción desde el widget.
  static Future<void> backgroundCallback(Uri? uri) async {
    if (uri == null) return;

    final db = DatabaseHelper.instance;
    final now = DateTime.now();

    switch (uri.host) {
      case 'add_hour_1':
        await db.insertEvent({
          'date': now.toIso8601String(),
          'title': 'Horas predicadas',
          'hours': 1.0,
          'category': 'Predicación',
        });
        break;
      case 'add_hour_30min':
        await db.insertEvent({
          'date': now.toIso8601String(),
          'title': 'Horas predicadas',
          'hours': 0.5,
          'category': 'Predicación',
        });
        break;
      case 'add_note':
        await db.insertNote({
          'date': now.toIso8601String(),
          'content': jsonEncode([{'insert': 'Nota rápida desde widget\n'}]),
          'isCompleted': 0,
          'isHandwritten': 0,
          'tags': jsonEncode([]),
          'audioPath': null,
          'isFavorite': 0,
        });
        break;
    }
    await updateWidgetData();
  }

  /// Actualiza los datos que se muestran en el widget.
  static Future<void> updateWidgetData() async {
    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    // Cálculo de horas semanales y mensuales
    final weekEvents = await db.getEventsByPeriod(startOfWeek, endOfWeek);
    final monthEvents = await db.getEventsByPeriod(startOfMonth, endOfMonth);
    final weekHours = weekEvents.fold<double>(
        0.0,
        (sum, event) =>
            sum + ((event['hours'] as num?)?.toDouble() ?? 0.0));
    final monthHours = monthEvents.fold<double>(
        0.0,
        (sum, event) =>
            sum + ((event['hours'] as num?)?.toDouble() ?? 0.0));
    final goal = await db.getGoal(now.year);
    final monthGoal = goal / 12;

    // Obtención de notas y eventos
    final allNotes = await db.getAllNotes();
    final notes = allNotes
        .where((note) => note['isFavorite'] == 1)
        .take(3)
        .map((note) =>
            _parseNoteContent(note['content'], note['isHandwritten'] == 1))
        .toList();
    final events = (await db.getEventsByPeriod(
            now, now.add(const Duration(days: 7))))
        .take(3)
        .map((event) => event['title'] as String)
        .toList();

    // Preferencias configuradas para el widget
    final showHours = prefs.getBool('widget_show_hours') ?? true;
    final showNotes = prefs.getBool('widget_show_notes') ?? true;
    final showEvents = prefs.getBool('widget_show_events') ?? true;
    final theme = prefs.getString('themeMode') ?? 'system';

    // Guardar datos y actualizar widget
    await HomeWidget.saveWidgetData('weekHours', weekHours);
    await HomeWidget.saveWidgetData('monthHours', monthHours);
    await HomeWidget.saveWidgetData('monthGoal', monthGoal);
    await HomeWidget.saveWidgetData('notes', jsonEncode(notes));
    await HomeWidget.saveWidgetData('events', jsonEncode(events));
    await HomeWidget.saveWidgetData('showHours', showHours);
    await HomeWidget.saveWidgetData('showNotes', showNotes);
    await HomeWidget.saveWidgetData('showEvents', showEvents);
    await HomeWidget.saveWidgetData('theme', theme);
    await HomeWidget.updateWidget(name: widgetName);
  }

  /// Parsea el contenido de una nota para mostrarla en el widget.
  static String _parseNoteContent(String content, bool isHandwritten) {
    if (isHandwritten) return 'Nota manuscrita';
    try {
      final delta = jsonDecode(content) as List;
      return delta.map((op) => op['insert']?.toString() ?? '').join();
    } catch (e) {
      return content;
    }
  }
}
