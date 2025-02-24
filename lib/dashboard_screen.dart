import 'package:flutter/material.dart';
import 'package:calendar_app/calendar_screen.dart';
import 'package:calendar_app/report_screen.dart';
import 'package:calendar_app/notes_screen.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:calendar_app/notification_helper.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _monthHours = 0.0;
  double _monthGoal = 600.0; // Meta mensual asumida (meta anual / 12).
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _favoriteNotes = [];
  Map<String, dynamic> _globalStats = {};
  int _pendingNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    // Horas y meta del mes.
    _monthHours = await db.getMonthlyHours(now);
    _monthGoal = (await db.getGoal(now.year)) / 12;

    // Eventos próximos (en los siguientes 7 días).
    _upcomingEvents = await db.getEventsByPeriod(
      now,
      now.add(const Duration(days: 7)),
    );

    // Notas favoritas.
    final allNotes = await db.getAllNotes();
    _favoriteNotes = allNotes.where((note) => note['isFavorite'] == 1).toList();

    // Estadísticas globales (horas totales, total de eventos y notas).
    final dbInstance = await db.database; // Obtenemos la instancia real de la DB de sqflite.
    final totalHoursResult = await dbInstance.rawQuery('SELECT SUM(hours) as totalHours FROM events');
    final totalNotesResult = await dbInstance.rawQuery('SELECT COUNT(*) as totalNotes FROM notes');
    final totalEventsResult = await dbInstance.rawQuery('SELECT COUNT(*) as totalEvents FROM events');

    _globalStats = {
      'totalHours': totalHoursResult.first['totalHours'] as double? ?? 0.0,
      'totalNotes': totalNotesResult.first['totalNotes'] as int? ?? 0,
      'totalEvents': totalEventsResult.first['totalEvents'] as int? ?? 0,
    };

    // Notificaciones pendientes.
    final pending = await NotificationHelper.getPendingNotifications();
    _pendingNotifications = pending.length;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMonthProgressCard(),
              const SizedBox(height: 16),
              _buildUpcomingEventsCard(),
              const SizedBox(height: 16),
              _buildFavoriteNotesCard(),
              const SizedBox(height: 16),
              _buildNotificationsCard(),
              const SizedBox(height: 16),
              _buildGlobalStatsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthProgressCard() {
    final now = DateTime.now();
    final progress = _monthHours / _monthGoal;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progreso de ${DateFormat('MMMM yyyy').format(now)}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${_monthHours.toStringAsFixed(2)} de $_monthGoal h',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress > 1 ? 1 : progress,
              backgroundColor: Theme.of(context).dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 8),
            Text('${(progress * 100).toStringAsFixed(1)}% de la meta mensual'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Ver Informe Completo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Eventos Próximos (7 días)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_upcomingEvents.isEmpty)
              const Text('No hay eventos próximos.')
            else
              ..._upcomingEvents.take(3).map(
                (event) => ListTile(
                  title: Text(event['title']),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(event['date']))} - ${event['category']}',
                  ),
                  trailing: event['hours'] > 0
                      ? Text('${(event['hours'] as num).toDouble().toStringAsFixed(2)} h')
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CalendarScreen()),
                  ),
                ),
              ),
            if (_upcomingEvents.length > 3)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
                child: const Text('Ver más'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteNotesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notas Favoritas',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_favoriteNotes.isEmpty)
              const Text('No hay notas favoritas.')
            else
              ..._favoriteNotes.take(5).map(
                (note) => ListTile(
                  title: Text(
                    note['isHandwritten'] == 1
                        ? 'Nota manuscrita'
                        : _parseNoteContent(note['content']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(
                      DateTime.parse(note['date']),
                    ),
                  ),
                  leading: const Icon(Icons.star, color: Colors.yellow),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotesScreen()),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotesScreen()),
              ),
              child: const Text('Ver todas las notas'),
            ),
          ],
        ),
      ),
    );
  }

  String _parseNoteContent(String content) {
    try {
      final delta = jsonDecode(content) as List;
      return delta.map((op) => op['insert']?.toString() ?? '').join();
    } catch (e) {
      return content;
    }
  }

  Widget _buildNotificationsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Notificaciones Pendientes',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Row(
              children: [
                const Icon(Icons.notifications, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  '$_pendingNotifications',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalStatsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estadísticas Globales',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Horas Totales',
                  _globalStats['totalHours']?.toStringAsFixed(2) ?? '0.0',
                  Icons.timer,
                ),
                _buildStatItem(
                  'Eventos',
                  _globalStats['totalEvents']?.toString() ?? '0',
                  Icons.event,
                ),
                _buildStatItem(
                  'Notas',
                  _globalStats['totalNotes']?.toString() ?? '0',
                  Icons.note,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 32),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
