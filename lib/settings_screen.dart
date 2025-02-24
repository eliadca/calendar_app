import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_app/main.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:calendar_app/notification_helper.dart';
import 'package:calendar_app/widget_helper.dart';
import 'onboarding_screen.dart'; // Asegúrate de que la ruta sea la correcta según tu estructura

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _goalController;
  bool _vibrationEnabled = true;
  String _notificationSound = 'default';
  int _selectedYear = DateTime.now().year;
  String _dateFormat = '24h';
  String _textSize = 'medium';
  String _language = 'es';
  bool _widgetShowHours = true;
  bool _widgetShowNotes = true;
  bool _widgetShowEvents = true;

  @override
  void initState() {
    super.initState();
    _goalController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;
    final goal = await db.getGoal(_selectedYear);
    setState(() {
      _vibrationEnabled = prefs.getBool('notificationVibration') ?? true;
      _notificationSound = prefs.getString('notificationSound') ?? 'default';
      _goalController.text = goal.toString();
      _dateFormat = prefs.getString('dateFormat') ?? '24h';
      _textSize = prefs.getString('textSize') ?? 'medium';
      _language = prefs.getString('language') ?? 'es';
      _widgetShowHours = prefs.getBool('widget_show_hours') ?? true;
      _widgetShowNotes = prefs.getBool('widget_show_notes') ?? true;
      _widgetShowEvents = prefs.getBool('widget_show_events') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationVibration', _vibrationEnabled);
    await prefs.setString('notificationSound', _notificationSound);
    await prefs.setString('dateFormat', _dateFormat);
    await prefs.setString('textSize', _textSize);
    await prefs.setString('language', _language);
    await prefs.setBool('widget_show_hours', _widgetShowHours);
    await prefs.setBool('widget_show_notes', _widgetShowNotes);
    await prefs.setBool('widget_show_events', _widgetShowEvents);
    final goal = double.tryParse(_goalController.text) ?? 600.0;
    await DatabaseHelper.instance.setGoal(_selectedYear, goal);
    await WidgetHelper.updateWidgetData();
  }

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = _getTextScaleFactor();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _language == 'es' ? 'Ajustes' : 'Settings',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(_language == 'es' ? 'Apariencia' : 'Appearance'),
              _buildAppearanceSettings(),
              const SizedBox(height: 16),
              _buildSectionTitle(_language == 'es' ? 'Notificaciones' : 'Notifications'),
              _buildNotificationSettings(),
              const SizedBox(height: 16),
              _buildSectionTitle(_language == 'es' ? 'Metas' : 'Goals'),
              _buildGoalSettings(),
              const SizedBox(height: 16),
              _buildSectionTitle(_language == 'es' ? 'Widget' : 'Widget'),
              _buildWidgetSettings(),
              const SizedBox(height: 16),
              _buildSectionTitle(_language == 'es' ? 'Datos' : 'Data'),
              _buildDataSettings(),
            ],
          ),
        ),
      ),
    );
  }

  double _getTextScaleFactor() {
    switch (_textSize) {
      case 'small':
        return 0.9;
      case 'medium':
        return 1.0;
      case 'large':
        return 1.2;
      default:
        return 1.0;
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headline6?.copyWith(fontSize: 20),
      ),
    );
  }

  Widget _buildAppearanceSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            title: Text(_language == 'es' ? 'Tema' : 'Theme'),
            trailing: Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) => DropdownButton<ThemeMode>(
                value: themeProvider.themeMode,
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(_language == 'es' ? 'Claro' : 'Light'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(_language == 'es' ? 'Oscuro' : 'Dark'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(_language == 'es' ? 'Sistema' : 'System'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    themeProvider.setTheme(value);
                  }
                },
              ),
            ),
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Formato de Fecha/Hora' : 'Date/Time Format'),
            trailing: DropdownButton<String>(
              value: _dateFormat,
              items: [
                DropdownMenuItem(
                  value: '12h',
                  child: Text(_language == 'es' ? '12 horas' : '12-hour'),
                ),
                DropdownMenuItem(
                  value: '24h',
                  child: Text(_language == 'es' ? '24 horas' : '24-hour'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _dateFormat = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Tamaño de Texto' : 'Text Size'),
            trailing: DropdownButton<String>(
              value: _textSize,
              items: [
                DropdownMenuItem(
                  value: 'small',
                  child: Text(_language == 'es' ? 'Pequeño' : 'Small'),
                ),
                DropdownMenuItem(
                  value: 'medium',
                  child: Text(_language == 'es' ? 'Mediano' : 'Medium'),
                ),
                DropdownMenuItem(
                  value: 'large',
                  child: Text(_language == 'es' ? 'Grande' : 'Large'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _textSize = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Idioma' : 'Language'),
            trailing: DropdownButton<String>(
              value: _language,
              items: [
                DropdownMenuItem(
                  value: 'es',
                  child: Text(_language == 'es' ? 'Español' : 'Spanish'),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Text(_language == 'es' ? 'Inglés' : 'English'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _language = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(_language == 'es' ? 'Vibración' : 'Vibration'),
            value: _vibrationEnabled,
            onChanged: (value) async {
              setState(() {
                _vibrationEnabled = value;
              });
              await _saveSettings();
            },
            activeColor: Theme.of(context).primaryColor,
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Sonido de Notificación' : 'Notification Sound'),
            trailing: DropdownButton<String>(
              value: _notificationSound,
              items: [
                DropdownMenuItem(
                  value: 'default',
                  child: Text(_language == 'es' ? 'Predeterminado' : 'Default'),
                ),
                DropdownMenuItem(
                  value: 'alert',
                  child: Text(_language == 'es' ? 'Alerta' : 'Alert'),
                ),
                DropdownMenuItem(
                  value: 'soft',
                  child: Text(_language == 'es' ? 'Suave' : 'Soft'),
                ),
              ],
              onChanged: (value) async {
                if (value != null) {
                  setState(() {
                    _notificationSound = value;
                  });
                  await _saveSettings();
                  await NotificationHelper.showInstantNotification(
                    title: _language == 'es' ? 'Prueba de Sonido' : 'Sound Test',
                    body: _language == 'es'
                        ? 'Este es un ejemplo de notificación.'
                        : 'This is a test notification.',
                    sound: value == 'default' ? null : value,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            title: Text(_language == 'es' ? 'Año' : 'Year'),
            trailing: DropdownButton<int>(
              value: _selectedYear,
              items: List.generate(
                      10, (index) => DateTime.now().year - 5 + index)
                  .map((year) => DropdownMenuItem(
                        value: year,
                        child: Text('$year-${year + 1}'),
                      ))
                  .toList(),
              onChanged: (value) async {
                if (value != null) {
                  setState(() {
                    _selectedYear = value;
                  });
                  final goal = await DatabaseHelper.instance.getGoal(_selectedYear);
                  setState(() {
                    _goalController.text = goal.toString();
                  });
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _goalController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: _language == 'es'
                    ? 'Ingresa tu meta (horas)'
                    : 'Enter your goal (hours)',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) async {
                await _saveSettings();
                final monthlyHours =
                    await DatabaseHelper.instance.getMonthlyHours(DateTime.now());
                await NotificationHelper.checkGoalNotification(_selectedYear, monthlyHours);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(_language == 'es'
                ? 'Mostrar Horas en Widget'
                : 'Show Hours in Widget'),
            value: _widgetShowHours,
            onChanged: (value) async {
              setState(() {
                _widgetShowHours = value;
              });
              await _saveSettings();
            },
            activeColor: Theme.of(context).primaryColor,
          ),
          SwitchListTile(
            title: Text(_language == 'es'
                ? 'Mostrar Notas en Widget'
                : 'Show Notes in Widget'),
            value: _widgetShowNotes,
            onChanged: (value) async {
              setState(() {
                _widgetShowNotes = value;
              });
              await _saveSettings();
            },
            activeColor: Theme.of(context).primaryColor,
          ),
          SwitchListTile(
            title: Text(_language == 'es'
                ? 'Mostrar Eventos en Widget'
                : 'Show Events in Widget'),
            value: _widgetShowEvents,
            onChanged: (value) async {
              setState(() {
                _widgetShowEvents = value;
              });
              await _saveSettings();
            },
            activeColor: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildDataSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            title: Text(_language == 'es' ? 'Respaldar Datos' : 'Backup Data'),
            trailing: const Icon(Icons.backup),
            onTap: () async {
              await DatabaseHelper.instance.backupDatabase();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_language == 'es'
                      ? 'Respaldo creado y compartido'
                      : 'Backup created and shared'),
                ),
              );
            },
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Restaurar Datos' : 'Restore Data'),
            trailing: const Icon(Icons.restore),
            onTap: () async {
              await DatabaseHelper.instance.restoreDatabase();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_language == 'es'
                      ? 'Datos restaurados'
                      : 'Data restored'),
                ),
              );
              setState(() {});
            },
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Reiniciar Tutorial' : 'Reset Tutorial'),
            trailing: const Icon(Icons.help),
            onTap: () {
              Provider.of<AppState>(context, listen: false).resetFirstRun();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
          ),
          ListTile(
            title: Text(_language == 'es' ? 'Borrar Todo' : 'Delete All'),
            trailing: const Icon(Icons.delete_forever, color: Colors.red),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(_language == 'es' ? 'Confirmar' : 'Confirm'),
                  content: Text(_language == 'es'
                      ? '¿Estás seguro de borrar todos los datos?'
                      : 'Are you sure you want to delete all data?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(_language == 'es' ? 'Cancelar' : 'Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(_language == 'es' ? 'Confirmar' : 'Confirm'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseHelper.instance.deleteAllData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_language == 'es'
                        ? 'Todos los datos han sido borrados'
                        : 'All data has been deleted'),
                  ),
                );
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }
}
