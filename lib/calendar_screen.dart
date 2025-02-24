import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:calendar_app/notification_helper.dart';
import 'package:calendar_app/notes_screen.dart';
import 'package:calendar_app/widget_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_calendar/device_calendar.dart' as device;
// Si usas TZDateTime, necesitas:
// import 'package:timezone/timezone.dart' as tz;

class CalendarEvent {
  final int id;
  final String title;
  final DateTime dateTime;
  final bool isReminder;
  final double hours;
  final String? reminderTime;
  final String category;
  final String? note;
  final String? recurrence;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.dateTime,
    this.isReminder = false,
    required this.hours,
    this.reminderTime,
    required this.category,
    this.note,
    this.recurrence,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<CalendarEvent>> _events = {};
  double _monthlyHours = 0.0;
  bool _isDayExpanded = false;
  String _searchQuery = '';
  String? _selectedCategory;
  bool _isListView = false;
  final TextEditingController _searchController = TextEditingController();
  final device.DeviceCalendarPlugin _deviceCalendarPlugin = device.DeviceCalendarPlugin();

  final Map<String, Color> _categoryColors = {
    'Predicación': Colors.green,
    'Reuniones': Colors.blue,
    'Personal': Colors.orange,
    'Otros': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents(_focusedDay);
  }

  Future<void> _loadEvents(DateTime date) async {
    // Obtenemos los eventos para la fecha "date"
    final eventsFromDB = await DatabaseHelper.instance.getEventsByDate(
      DateFormat('yyyy-MM-dd').format(date),
    );
    // Calculamos las horas del mes con date como referencia
    final hoursFromDB = await DatabaseHelper.instance.getMonthlyHours(date);

    setState(() {
      _events = {};
      for (var event in eventsFromDB) {
        final eventDate = DateTime.parse(event['date']);
        _events[eventDate] = [
          ...(_events[eventDate] ?? []),
          CalendarEvent(
            id: event['id'],
            title: event['title'],
            dateTime: eventDate,
            isReminder: event['isReminder'] == 1,
            hours: (event['hours'] as num?)?.toDouble() ?? 0.0,
            reminderTime: event['reminderTime'],
            category: event['category'] ?? 'Otros',
            note: event['note'],
            recurrence: event['recurrence'],
          ),
        ];
      }
      _monthlyHours = hoursFromDB;
      _applyFilters();
      _checkConflicts();
      // Actualizamos widget
      WidgetHelper.updateWidgetData();
    });
  }

  void _applyFilters() {
    if (_searchQuery.isEmpty && _selectedCategory == null) return;
    setState(() {
      _events = Map.from(_events)
        ..removeWhere((date, events) {
          return events.every((event) =>
              (_searchQuery.isNotEmpty && !event.title.toLowerCase().contains(_searchQuery.toLowerCase())) ||
              (_selectedCategory != null && event.category != _selectedCategory));
        });
    });
  }

  void _checkConflicts() {
    for (var dayEvents in _events.values) {
      dayEvents.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      for (int i = 0; i < dayEvents.length - 1; i++) {
        if (dayEvents[i].isReminder && dayEvents[i + 1].isReminder) {
          final start1 = dayEvents[i].dateTime;
          final end1 = dayEvents[i].reminderTime != null
              ? DateTime.parse(dayEvents[i].reminderTime!)
              : start1.add(const Duration(hours: 1));
          final start2 = dayEvents[i + 1].dateTime;
          if (start2.isBefore(end1)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Conflicto detectado el ${DateFormat('dd/MM/yyyy').format(start1)} '
                  'entre "${dayEvents[i].title}" y "${dayEvents[i + 1].title}"',
                ),
                action: SnackBarAction(
                  label: 'Resolver',
                  onPressed: () => _editEvent(dayEvents[i]),
                ),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = _focusedDay;
                _loadEvents(_focusedDay);
              });
            },
          ),
          IconButton(
            icon: Icon(_isListView ? Icons.calendar_view_month : Icons.list),
            onPressed: () => setState(() => _isListView = !_isListView),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportMonth,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncWithDeviceCalendar,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              _isListView ? _buildListView() : _buildCalendar(),
              if (!_isListView) _buildMonthlyHours(),
            ],
          ),
          if (_isDayExpanded && _selectedDay != null && !_isListView)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildExpandedDayDetails(),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar eventos...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _loadEvents(_focusedDay);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedCategory,
            hint: const Text('Categoría'),
            items: _categoryColors.keys
                .map((category) => DropdownMenuItem(value: category, child: Text(category)))
                .toList()
              ..add(const DropdownMenuItem(value: null, child: Text('Todas'))),
            onChanged: (value) {
              setState(() {
                _selectedCategory = value;
                _loadEvents(_focusedDay);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TableCalendar(
        firstDay: DateTime.utc(2000, 1, 1),
        lastDay: DateTime.utc(2050, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
            _isDayExpanded = true;
          });
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
          _loadEvents(focusedDay);
        },
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          weekendTextStyle: TextStyle(color: Theme.of(context).primaryColor),
          todayDecoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
          ),
          selectedDecoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
          ),
          cellMargin: const EdgeInsets.all(2.0),
          defaultTextStyle: const TextStyle(fontSize: 12),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          weekendStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          formatButtonShowsNext: false,
          formatButtonDecoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          formatButtonTextStyle: const TextStyle(color: Colors.white),
          titleCentered: true,
          titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            final events = _events[day] ?? [];
            final totalHours = events.fold<double>(0.0, (sum, e) => sum + e.hours);
            return GestureDetector(
              onPanUpdate: (details) {
                // Permite mover evento deslizando en la celda
                if (details.delta.dx.abs() > details.delta.dy.abs()) {
                  _moveEvent(day, details.delta.dx > 0 ? 1 : -1);
                }
              },
              child: Container(
                margin: const EdgeInsets.all(2.0),
                decoration: BoxDecoration(
                  color: events.isNotEmpty ? Theme.of(context).cardColor : null,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSameDay(day, _selectedDay) ? Theme.of(context).primaryColor : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(day.day.toString(), style: const TextStyle(fontSize: 12)),
                    if (totalHours > 0)
                      Positioned(
                        bottom: 1,
                        child: Text(
                          '${totalHours.toStringAsFixed(1)}h',
                          style: const TextStyle(fontSize: 8),
                        ),
                      ),
                    if (events.isNotEmpty)
                      Positioned(
                        top: 1,
                        left: 1,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _categoryColors[events.first.category],
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildListView() {
    final events = _events[_selectedDay] ?? [];
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEEE, d MMMM').format(_selectedDay!),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () => setState(() => _isListView = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? const Center(child: Text('No hay eventos para este día.'))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return ListTile(
                        leading: Icon(
                          event.isReminder ? Icons.alarm : Icons.work,
                          color: _categoryColors[event.category],
                        ),
                        title: Text(event.title),
                        subtitle: Text(
                          event.hours > 0
                              ? '${event.hours.toStringAsFixed(2)} h'
                              : event.note ?? 'Sin nota',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editEvent(event),
                            ),
                          ],
                        ),
                        onTap: () => _showEventDetails(event),
                      );
                    },
                  ),
          ),
          _buildQuickAddButtons(),
        ],
      ),
    );
  }

  Widget _buildMonthlyHours() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Horas del mes:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            '${_monthlyHours.toStringAsFixed(2)} h',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedDayDetails() {
    final events = _events[_selectedDay!] ?? [];
    final dailyTotal = events.fold<double>(0.0, (sum, e) => sum + e.hours);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado con la fecha y el botón de cerrar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE, d MMMM').format(_selectedDay!),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isDayExpanded = false;
                  });
                },
              ),
            ],
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No hay eventos ni horas registradas.'),
            )
          else
            ...events.map(
              (event) => ListTile(
                leading: Icon(
                  event.isReminder ? Icons.alarm : Icons.work,
                  color: _categoryColors[event.category],
                ),
                title: TextField(
                  controller: TextEditingController(text: event.title),
                  decoration: const InputDecoration(border: InputBorder.none),
                  onSubmitted: (value) => _updateEvent(event, title: value),
                ),
                subtitle: event.hours > 0
                    ? TextField(
                        controller: TextEditingController(text: event.hours.toStringAsFixed(2)),
                        decoration: const InputDecoration(border: InputBorder.none),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) => _updateEvent(event, hours: double.tryParse(value) ?? event.hours),
                      )
                    : event.note != null
                        ? Text(event.note!, style: const TextStyle(fontSize: 12))
                        : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (event.note == null)
                      IconButton(
                        icon: const Icon(Icons.note_add, size: 20),
                        onPressed: () => _addNoteToEvent(event),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editEvent(event),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Total del día: ${dailyTotal.toStringAsFixed(2)} h'),
          ),
          _buildQuickAddButtons(),
        ],
      ),
    );
  }

  Widget _buildQuickAddButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(
          icon: Icons.add,
          label: '+1h',
          onTap: () => _quickAddHours(1.0),
        ),
        _buildActionButton(
          icon: Icons.add,
          label: '+30min',
          onTap: () => _quickAddHours(0.5),
        ),
        _buildActionButton(
          icon: Icons.event,
          label: 'Evento',
          onTap: _addEvent,
        ),
        _buildActionButton(
          icon: Icons.note_add,
          label: 'Nota',
          onTap: _addNote,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _addEvent() async {
    final controller = TextEditingController();
    DateTime? reminderTime = _selectedDay;
    String category = 'Otros';
    String? recurrence;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nuevo Evento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Título del evento'),
              ),
              DropdownButton<String>(
                value: category,
                items: _categoryColors.keys
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (value) => setState(() => category = value!),
              ),
              TextButton(
                onPressed: () async {
                  reminderTime = await _showDateTimePicker();
                  setState(() {});
                },
                child: Text(
                  reminderTime != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(reminderTime!)
                      : 'Seleccionar recordatorio',
                ),
              ),
              DropdownButton<String?>(
                value: recurrence,
                hint: const Text('Recurrencia'),
                items: [null, 'daily', 'weekly', 'monthly']
                    .map((val) => DropdownMenuItem(value: val, child: Text(val ?? 'Ninguna')))
                    .toList(),
                onChanged: (value) => setState(() => recurrence = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context, {
                    'title': controller.text,
                    'reminderTime': reminderTime,
                    'category': category,
                    'recurrence': recurrence,
                  });
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      final eventId = await DatabaseHelper.instance.insertEvent({
        'date': _selectedDay!.toIso8601String(),
        'title': result['title'],
        'isReminder': result['reminderTime'] != null ? 1 : 0,
        'reminderTime': result['reminderTime']?.toIso8601String(),
        'hours': 0.0,
        'category': result['category'],
        'recurrence': result['recurrence'],
      });
      if (result['reminderTime'] != null) {
        await NotificationHelper.scheduleNotification(
          id: eventId,
          title: result['title'],
          body: '¡Es hora de tu evento!',
          scheduledTime: result['reminderTime'],
          recurrence: result['recurrence'],
        );
      }
      _loadEvents(_focusedDay);
    }
  }

  void _addHours() async {
    int hours = 0;
    int minutes = 0;
    String category = 'Predicación';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Registrar Horas Predicadas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: hours,
                items: List.generate(24, (index) => index)
                    .map((h) => DropdownMenuItem(value: h, child: Text('$h horas')))
                    .toList(),
                onChanged: (value) => setState(() => hours = value!),
              ),
              DropdownButton<int>(
                value: minutes,
                items: List.generate(12, (index) => index * 5)
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m minutos')))
                    .toList(),
                onChanged: (value) => setState(() => minutes = value!),
              ),
              DropdownButton<String>(
                value: category,
                items: _categoryColors.keys
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (value) => setState(() => category = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'hours': hours + minutes / 60,
                'category': category,
              }),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await DatabaseHelper.instance.insertEvent({
        'date': _selectedDay!.toIso8601String(),
        'title': 'Horas predicadas',
        'hours': result['hours'],
        'category': result['category'],
      });
      _loadEvents(_focusedDay);
    }
  }

  void _quickAddHours(double hours) async {
    await DatabaseHelper.instance.insertEvent({
      'date': _selectedDay!.toIso8601String(),
      'title': 'Horas predicadas',
      'hours': hours,
      'category': 'Predicación',
    });
    _loadEvents(_focusedDay);
  }

  void _addNote() async {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NotesScreen()));
  }

  void _addNoteToEvent(CalendarEvent event) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Nota al Evento'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Escribe una nota...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.updateEvent({
        'id': event.id,
        'date': event.dateTime.toIso8601String(),
        'title': event.title,
        'isReminder': event.isReminder ? 1 : 0,
        'reminderTime': event.reminderTime,
        'hours': event.hours,
        'category': event.category,
        'note': result,
        'recurrence': event.recurrence,
      });
      _loadEvents(_focusedDay);
    }
  }

  void _editEvent(CalendarEvent event) async {
    final controller = TextEditingController(text: event.title);
    DateTime? reminderTime =
        event.reminderTime != null ? DateTime.parse(event.reminderTime!) : null;
    double hours = event.hours;
    String category = event.category;
    String? note = event.note;
    String? recurrence = event.recurrence;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Editar Evento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(hintText: 'Título del evento'),
                ),
                DropdownButton<String>(
                  value: category,
                  items: _categoryColors.keys
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (value) => setState(() => category = value!),
                ),
                if (event.isReminder)
                  TextButton(
                    onPressed: () async {
                      reminderTime = await _showDateTimePicker();
                      setState(() {});
                    },
                    child: Text(
                      reminderTime != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(reminderTime!)
                          : 'Seleccionar recordatorio',
                    ),
                  ),
                if (event.title == 'Horas predicadas') ...[
                  DropdownButton<double>(
                    value: hours.floorToDouble(),
                    items: List.generate(24, (index) => index.toDouble())
                        .map((h) => DropdownMenuItem(value: h, child: Text('$h horas')))
                        .toList(),
                    onChanged: (value) => setState(() => hours = value! + (hours - hours.floor())),
                  ),
                  DropdownButton<double>(
                    value: (hours - hours.floor()) * 60,
                    items: List.generate(12, (index) => index * 5.0)
                        .map((m) => DropdownMenuItem(value: m, child: Text('$m minutos')))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => hours = hours.floor() + value! / 60),
                  ),
                ],
                TextField(
                  controller: TextEditingController(text: note),
                  decoration: const InputDecoration(hintText: 'Nota (opcional)'),
                  onChanged: (value) => note = value,
                ),
                DropdownButton<String?>(
                  value: recurrence,
                  hint: const Text('Recurrencia'),
                  items: [null, 'daily', 'weekly', 'monthly']
                      .map((val) => DropdownMenuItem(value: val, child: Text(val ?? 'Ninguna')))
                      .toList(),
                  onChanged: (value) => setState(() => recurrence = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context, {
                    'title': controller.text,
                    'reminderTime': reminderTime,
                    'hours': hours,
                    'category': category,
                    'note': note,
                    'recurrence': recurrence,
                  });
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await DatabaseHelper.instance.updateEvent({
        'id': event.id,
        'date': _selectedDay!.toIso8601String(),
        'title': result['title'],
        'isReminder': result['reminderTime'] != null ? 1 : 0,
        'reminderTime': result['reminderTime']?.toIso8601String(),
        'hours': result['hours'],
        'category': result['category'],
        'note': result['note'],
        'recurrence': result['recurrence'],
      });
      if (result['reminderTime'] != null) {
        await NotificationHelper.cancelNotification(event.id);
        await NotificationHelper.scheduleNotification(
          id: event.id,
          title: result['title'],
          body: '¡Es hora de tu evento!',
          scheduledTime: result['reminderTime'],
          recurrence: result['recurrence'],
        );
      }
      _loadEvents(_focusedDay);
    }
  }

  void _updateEvent(CalendarEvent event, {String? title, double? hours}) async {
    await DatabaseHelper.instance.updateEvent({
      'id': event.id,
      'date': event.dateTime.toIso8601String(),
      'title': title ?? event.title,
      'isReminder': event.isReminder ? 1 : 0,
      'reminderTime': event.reminderTime,
      'hours': hours ?? event.hours,
      'category': event.category,
      'note': event.note,
      'recurrence': event.recurrence,
    });
    _loadEvents(_focusedDay);
  }

  void _moveEvent(DateTime fromDay, int direction) async {
    final events = _events[fromDay] ?? [];
    if (events.isEmpty) return;
    final event = events.first;
    final newDate = fromDay.add(Duration(days: direction));

    await DatabaseHelper.instance.updateEvent({
      'id': event.id,
      'date': newDate.toIso8601String(),
      'title': event.title,
      'isReminder': event.isReminder ? 1 : 0,
      'reminderTime': event.reminderTime,
      'hours': event.hours,
      'category': event.category,
      'note': event.note,
      'recurrence': event.recurrence,
    });

    if (event.isReminder && event.reminderTime != null) {
      await NotificationHelper.cancelNotification(event.id);
      await NotificationHelper.scheduleNotification(
        id: event.id,
        title: event.title,
        body: '¡Es hora de tu evento!',
        scheduledTime: DateTime.parse(event.reminderTime!),
        recurrence: event.recurrence,
      );
    }
    _loadEvents(_focusedDay);
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_view_week),
              title: const Text('Vista Semanal'),
              onTap: () {
                setState(() => _calendarFormat = CalendarFormat.week);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_month),
              title: const Text('Vista Mensual'),
              onTap: () {
                setState(() => _calendarFormat = CalendarFormat.month);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_day),
              title: const Text('Vista de Dos Semanas'),
              onTap: () {
                setState(() => _calendarFormat = CalendarFormat.twoWeeks);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Vista Anual'),
              onTap: () {
                _showYearView();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showYearView() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Año ${_focusedDay.year}', style: Theme.of(context).textTheme.headlineMedium),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.count(
            crossAxisCount: 4,
            children: List.generate(12, (index) {
              final month = DateTime(_focusedDay.year, index + 1, 1);
              final monthlyHours = _events.entries
                  .where((e) => e.key.month == month.month && e.key.year == month.year)
                  .fold<double>(
                    0.0,
                    (sum, e) => sum + e.value.fold<double>(0.0, (s, ev) => s + ev.hours),
                  );
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _focusedDay = month;
                    _selectedDay = month;
                    _calendarFormat = CalendarFormat.month;
                    _loadEvents(_focusedDay);
                  });
                  Navigator.pop(context);
                },
                child: Card(
                  color: monthlyHours > 0 ? Colors.green.withOpacity(0.3) : null,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('MMM').format(month)),
                        if (monthlyHours > 0)
                          Text(
                            '${monthlyHours.toStringAsFixed(1)}h',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportMonth() async {
    final pdf = pw.Document();
    final events = _events.entries
        .where((e) => e.key.month == _focusedDay.month && e.key.year == _focusedDay.year)
        .toList();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: [
            pw.Text(
              'Calendario - ${DateFormat('MMMM yyyy').format(_focusedDay)}',
              style: const pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Fecha', 'Título', 'Horas', 'Categoría', 'Nota'],
              data: events
                  .map((e) => e.value.map((event) => [
                        DateFormat('dd/MM').format(event.dateTime),
                        event.title,
                        event.hours.toStringAsFixed(2),
                        event.category,
                        event.note ?? '',
                      ]).toList())
                  .expand((x) => x)
                  .toList(),
            ),
          ],
        ),
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/calendar_${DateFormat('yyyyMM').format(_focusedDay)}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Calendario de ${DateFormat('MMMM yyyy').format(_focusedDay)}',
    );
  }

  Future<void> _syncWithDeviceCalendar() async {
    final status = await Permission.calendar.request();
    if (status.isGranted) {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null && calendarsResult.data!.isNotEmpty) {
        final calendarId = calendarsResult.data!.first.id!;
        final events = _events.entries
            .where((e) => e.key.month == _focusedDay.month && e.key.year == _focusedDay.year)
            .expand((e) => e.value)
            .toList();

        for (var event in events) {
          // Si usas tz, debes convertir a tz.TZDateTime:
          final start = event.dateTime; 
          final end = event.reminderTime != null
              ? DateTime.parse(event.reminderTime!)
              : event.dateTime.add(const Duration(hours: 1));

          final deviceEvent = device.Event(
            calendarId,
            title: event.title,
            start: start,
            end: end,
            description: event.note,
          );
          await _deviceCalendarPlugin.createOrUpdateEvent(deviceEvent);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eventos sincronizados con el calendario del dispositivo')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron calendarios en el dispositivo')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de calendario denegado')),
      );
    }
  }

  void _showEventDetails(CalendarEvent event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(event.dateTime)}'),
            if (event.hours > 0) Text('Horas: ${event.hours.toStringAsFixed(2)} h'),
            Text('Categoría: ${event.category}'),
            if (event.note != null) Text('Nota: ${event.note}'),
            if (event.isReminder && event.reminderTime != null)
              Text(
                'Recordatorio: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(event.reminderTime!))}',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _editEvent(event);
            },
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _showDateTimePicker() async {
    // Seleccionamos fecha
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (date != null) {
      // Seleccionamos hora
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDay ?? DateTime.now()),
      );
      if (time != null) {
        return DateTime(date.year, date.month, date.day, time.hour, time.minute);
      }
    }
    return null;
  }
}
