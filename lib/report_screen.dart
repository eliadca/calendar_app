import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({Key? key}) : super(key: key);

  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _selectedYear = DateTime.now().year;
  String _viewMode = 'year'; // 'year', 'week'
  DateTime _selectedWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  Map<DateTime, double> _periodHours = {};
  Map<String, double> _categoryTotals = {};
  double _totalHours = 0.0;
  double _remainingHours = 600.0;
  double _carryOver = 0.0;
  double _goalHours = 600.0;
  String _reportNotes = '';
  Map<DateTime, String> _monthlyNotes = {};
  bool _showDetails = false;
  bool _comparePrevious = false;
  Map<DateTime, double> _previousPeriodHours = {};
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _loadReport(_selectedYear);
  }

  Future<void> _loadReport(int year) async {
    final startDate = _viewMode == 'year'
        ? DateTime(year - 1, 9, 1)
        : _selectedWeekStart;
    final endDate = _viewMode == 'year'
        ? DateTime(year, 8, 31)
        : _selectedWeekStart.add(const Duration(days: 6));

    final events = await DatabaseHelper.instance.getEventsByPeriod(startDate, endDate);
    final prefs = await SharedPreferences.getInstance();
    _goalHours = prefs.getDouble('goalHours') ?? 600.0;

    setState(() {
      _periodHours = {};
      _categoryTotals = {};
      for (var event in events) {
        final date = DateTime.parse(event['date']);
        final key = _viewMode == 'year'
            ? DateTime(date.year, date.month, 1)
            : date;

        if (_selectedTag == null || event['category'] == _selectedTag) {
          _periodHours[key] = (_periodHours[key] ?? 0.0) +
              ((event['hours'] as num?)?.toDouble() ?? 0.0);

          final category = event['category'] as String;
          _categoryTotals[category] = (_categoryTotals[category] ?? 0.0) +
              ((event['hours'] as num?)?.toDouble() ?? 0.0);
        }
      }

      _totalHours = _periodHours.values.fold(0.0, (sum, hours) => sum + hours);
      _remainingHours = _goalHours - _totalHours;
      _carryOver = _calculateCarryOver();
      _reportNotes = prefs.getString('reportNotes_$_selectedYear') ?? '';
      _loadMonthlyNotes();

      if (_comparePrevious && _viewMode == 'year') {
        _loadPreviousPeriod(year - 1);
      }
    });
  }

  Future<void> _loadPreviousPeriod(int previousYear) async {
    final startDate = DateTime(previousYear - 1, 9, 1);
    final endDate = DateTime(previousYear, 8, 31);
    final events = await DatabaseHelper.instance.getEventsByPeriod(startDate, endDate);

    setState(() {
      _previousPeriodHours = {};
      for (var event in events) {
        final date = DateTime.parse(event['date']);
        final key = DateTime(date.year, date.month, 1);
        if (_selectedTag == null || event['category'] == _selectedTag) {
          _previousPeriodHours[key] = (_previousPeriodHours[key] ?? 0.0) +
              ((event['hours'] as num?)?.toDouble() ?? 0.0);
        }
      }
    });
  }

  Future<void> _loadMonthlyNotes() async {
    final prefs = await SharedPreferences.getInstance();
    _monthlyNotes = {};
    for (int month = 1; month <= 12; month++) {
      final key = 'monthlyNote_${_selectedYear}_$month';
      _monthlyNotes[DateTime(_selectedYear, month, 1)] =
          prefs.getString(key) ?? '';
    }
  }

  double _calculateCarryOver() {
    double carryOver = 0.0;
    for (var hours in _periodHours.values) {
      // Ejemplo: si hay límite de 50 horas mensuales
      if (_viewMode == 'year' && hours > 50) {
        carryOver += hours - 50;
      }
    }
    return carryOver;
  }

  Future<double> _getWeekHours() async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final events = await DatabaseHelper.instance.getEventsByPeriod(startOfWeek, endOfWeek);

    return events.fold(
      0.0,
      (sum, event) => sum + ((event['hours'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _showFilterOptions,
          ),
          IconButton(
            icon: Icon(_showDetails ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showDetails = !_showDetails),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildWeekSummary(),
            _buildSummary(),
            _buildCategoryBreakdown(),
            _buildPeriodDetails(),
            _buildTrends(),
            if (_carryOver > 0) _buildCarryOverCard(),
            _buildReportNotes(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSummary() {
    return FutureBuilder<double>(
      future: _getWeekHours(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final weekHours = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Horas esta semana', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${weekHours.toStringAsFixed(2)} h', style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary() {
    final progress = _totalHours / _goalHours;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                _viewMode == 'year'
                    ? 'Año ${_selectedYear - 1}-$_selectedYear (Sep-Ago)'
                    : 'Semana del ${DateFormat('dd/MM').format(_selectedWeekStart)} al ${DateFormat('dd/MM').format(_selectedWeekStart.add(const Duration(days: 6)))}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    label: 'Total Horas',
                    value: _totalHours.toStringAsFixed(2),
                    color: Colors.blueAccent,
                  ),
                  _buildSummaryItem(
                    label: 'Restantes',
                    value: _remainingHours.toStringAsFixed(2),
                    color: _remainingHours >= 0 ? Colors.green : Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress > 1 ? 1 : progress,
                backgroundColor: Theme.of(context).dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
              ),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(1)}% de la meta ($_goalHours h)'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem({required String label, required String value, required Color color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildCategoryBreakdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Horas por Categoría', style: Theme.of(context).textTheme.headlineMedium),
            ),
            ..._categoryTotals.entries.map((entry) => ListTile(
                  title: Text(entry.key),
                  trailing: Text('${entry.value.toStringAsFixed(2)} h'),
                  leading: Icon(Icons.circle, color: _getCategoryColor(entry.key), size: 12),
                )),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    const colors = {
      'Predicación': Colors.green,
      'Reuniones': Colors.blue,
      'Personal': Colors.orange,
      'Otros': Colors.grey,
    };
    return colors[category] ?? Colors.grey;
  }

  Widget _buildPeriodDetails() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ExpansionTile(
          title: Text(
            _viewMode == 'year' ? 'Detalles por Mes' : 'Detalles por Día',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          children: _periodHours.entries.map((entry) {
            final previousHours = _previousPeriodHours[entry.key] ?? 0.0;
            final monthlyNote = _monthlyNotes[entry.key] ?? '';
            return ListTile(
              title: Text(
                _viewMode == 'year'
                    ? DateFormat('MMMM yyyy').format(entry.key)
                    : DateFormat('dd/MM/yyyy').format(entry.key),
              ),
              subtitle: monthlyNote.isNotEmpty
                  ? Text(monthlyNote, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${entry.value.toStringAsFixed(2)} h'),
                  if (_comparePrevious && _viewMode == 'year')
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        '(${entry.value - previousHours >= 0 ? '+' : ''}${(entry.value - previousHours).toStringAsFixed(2)})',
                        style: TextStyle(
                          color: entry.value - previousHours >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: _showDetails ? () => _showPeriodDetails(entry.key) : null,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTrends() {
    if (_viewMode != 'year') return const SizedBox.shrink();
    final averageHours = _totalHours / 12;
    final maxMonth = _periodHours.entries.fold<MapEntry<DateTime, double>>(
      MapEntry(DateTime.now(), 0.0),
      (prev, curr) => curr.value > prev.value ? curr : prev,
    );
    final minMonth = _periodHours.entries.fold<MapEntry<DateTime, double>>(
      MapEntry(DateTime.now(), double.infinity),
      (prev, curr) => curr.value < prev.value ? curr : prev,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tendencias', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Promedio mensual: ${averageHours.toStringAsFixed(2)} h'),
              Text('Mes más activo: ${DateFormat('MMMM').format(maxMonth.key)} (${maxMonth.value.toStringAsFixed(2)} h)'),
              Text('Mes menos activo: ${DateFormat('MMMM').format(minMonth.key)} (${minMonth.value.toStringAsFixed(2)} h)'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarryOverCard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.orange[100],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Horas sobrantes: ${_carryOver.toStringAsFixed(2)} h\nSe trasladan al siguiente período.',
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportNotes() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Se elimina la llave sobrante al final de la cadena
              Text(
                'Notas del Informe ${_selectedYear - 1}-$_selectedYear',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: _reportNotes),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Añade notas sobre este período...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) async {
                  _reportNotes = value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('reportNotes_$_selectedYear', value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Vista Anual'),
                onTap: () {
                  setState(() {
                    _viewMode = 'year';
                    _loadReport(_selectedYear);
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_week),
                title: const Text('Vista Semanal'),
                onTap: () {
                  setState(() {
                    _viewMode = 'week';
                    _loadReport(_selectedYear);
                  });
                  Navigator.pop(context);
                },
              ),
              if (_viewMode == 'week')
                ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: const Text('Semana Anterior'),
                  onTap: () {
                    setState(() {
                      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
                      _loadReport(_selectedYear);
                    });
                    Navigator.pop(context);
                  },
                ),
              if (_viewMode == 'week')
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: const Text('Semana Siguiente'),
                  onTap: () {
                    setState(() {
                      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
                      _loadReport(_selectedYear);
                    });
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.compare),
                title: const Text('Comparar con Año Anterior'),
                trailing: Switch(
                  value: _comparePrevious,
                  onChanged: (value) {
                    setState(() {
                      _comparePrevious = value;
                      _loadReport(_selectedYear);
                    });
                  },
                ),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.label),
                title: const Text('Filtrar por Etiqueta'),
                trailing: DropdownButton<String>(
                  value: _selectedTag,
                  hint: const Text('Todas'),
                  items: ['Predicación', 'Reuniones', 'Personal', 'Otros']
                      .map((tag) => DropdownMenuItem(value: tag, child: Text(tag)))
                      .toList()
                    ..add(const DropdownMenuItem(value: null, child: Text('Todas'))),
                  onChanged: (value) {
                    setState(() {
                      _selectedTag = value;
                      _loadReport(_selectedYear);
                    });
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Cambiar Año'),
                onTap: () {
                  _showYearPicker();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showYearPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(10, (index) {
            final year = DateTime.now().year - 5 + index;
            return ListTile(
              title: Text('$year-${year + 1}'),
              trailing: _selectedYear == year ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() {
                  _selectedYear = year;
                  _loadReport(year);
                });
                Navigator.pop(context);
              },
            );
          }),
        ),
      ),
    );
  }

  void _showPeriodDetails(DateTime period) async {
    final events = _viewMode == 'year'
        ? await DatabaseHelper.instance.getEventsByMonth(period)
        : await DatabaseHelper.instance.getEventsByDate(DateFormat('yyyy-MM-dd').format(period));

    final monthlyNote = _monthlyNotes[period] ?? '';
    final noteController = TextEditingController(text: monthlyNote);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _viewMode == 'year'
              ? DateFormat('MMMM yyyy').format(period)
              : DateFormat('dd/MM/yyyy').format(period),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Horas registradas: ${_periodHours[period]!.toStringAsFixed(2)} h',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (_viewMode == 'year')
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Nota para este mes...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) async {
                    _monthlyNotes[period] = value;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('monthlyNote_${_selectedYear}_${period.month}', value);
                  },
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                width: double.maxFinite,
                child: ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      title: Text(event['title']),
                      subtitle: Text(
                        '${(event['hours'] as num?)?.toDouble() ?? 0.0}h - ${event['category']}',
                      ),
                      trailing: event['note'] != null ? const Icon(Icons.note) : null,
                    );
                  },
                ),
              ),
            ],
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

  Future<void> _exportReport() async {
    final pdf = pw.Document();
    final startDate = _viewMode == 'year'
        ? DateTime(_selectedYear - 1, 9, 1)
        : _selectedWeekStart;
    final endDate = _viewMode == 'year'
        ? DateTime(_selectedYear, 8, 31)
        : _selectedWeekStart.add(const Duration(days: 6));
    final events = await DatabaseHelper.instance.getEventsByPeriod(startDate, endDate);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _viewMode == 'year'
                  ? 'Informe Anual ${_selectedYear - 1}-$_selectedYear'
                  : 'Informe Semanal ${DateFormat('dd/MM').format(_selectedWeekStart)}-${DateFormat('dd/MM').format(endDate)}',
              style: const pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Total Horas: $_totalHours h'),
            pw.Text('Meta: $_goalHours h'),
            pw.Text('Restantes: $_remainingHours h'),
            if (_carryOver > 0) pw.Text('Horas sobrantes: $_carryOver h'),
            pw.SizedBox(height: 20),
            pw.Text('Desglose por Categoría:', style: const pw.TextStyle(fontSize: 18)),
            ..._categoryTotals.entries.map((e) => pw.Text('${e.key}: ${e.value.toStringAsFixed(2)} h')),
            pw.SizedBox(height: 20),
            pw.Text('Eventos:', style: const pw.TextStyle(fontSize: 18)),
            pw.Table.fromTextArray(
              headers: ['Fecha', 'Título', 'Horas', 'Categoría', 'Nota'],
              data: events.map((event) => [
                DateFormat('dd/MM/yyyy').format(DateTime.parse(event['date'])),
                event['title'],
                ((event['hours'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                event['category'],
                event['note'] ?? '',
              ]).toList(),
            ),
            if (_reportNotes.isNotEmpty || _monthlyNotes.values.any((note) => note.isNotEmpty)) ...[
              pw.SizedBox(height: 20),
              pw.Text('Notas:', style: const pw.TextStyle(fontSize: 18)),
              if (_reportNotes.isNotEmpty) pw.Text('Año: $_reportNotes'),
              if (_viewMode == 'year')
                ..._monthlyNotes.entries
                    .where((entry) => entry.value.isNotEmpty)
                    .map((entry) => pw.Text('${DateFormat('MMMM').format(entry.key)}: ${entry.value}')),
            ],
          ],
        ),
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/report_${_viewMode == 'year' ? _selectedYear : DateFormat('yyyyMMdd').format(_selectedWeekStart)}.pdf',
    );
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: _viewMode == 'year'
          ? 'Informe Anual ${_selectedYear - 1}-$_selectedYear'
          : 'Informe Semanal ${DateFormat('dd/MM').format(_selectedWeekStart)}',
    );
  }
}
