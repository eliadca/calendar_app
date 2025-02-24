import 'package:flutter/material.dart';
import 'package:calendar_app/calendar_screen.dart';
import 'package:calendar_app/report_screen.dart';
import 'package:calendar_app/notes_screen.dart';
import 'package:calendar_app/notification_helper.dart';
import 'package:calendar_app/settings_screen.dart';
import 'package:calendar_app/dashboard_screen.dart';
import 'package:calendar_app/widget_helper.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationHelper.init();
  await WidgetHelper.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const CalendarApp(),
    ),
  );
}

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    notifyListeners();
    await WidgetHelper.updateWidgetData();
  }
}

class AppState with ChangeNotifier {
  bool _isFirstRun = true;

  bool get isFirstRun => _isFirstRun;

  AppState() {
    _checkFirstRun();
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    _isFirstRun = prefs.getBool('isFirstRun') ?? true;
    if (_isFirstRun) {
      await prefs.setBool('isFirstRun', false);
    }
    notifyListeners();
  }

  Future<void> resetFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstRun', true);
    _isFirstRun = true;
    notifyListeners();
  }
}

class CalendarApp extends StatelessWidget {
  const CalendarApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, AppState>(
      builder: (context, themeProvider, appState, child) {
        return MaterialApp(
          title: 'Smart Calendar',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.blueAccent,
            scaffoldBackgroundColor: Colors.white,
            cardColor: Colors.grey[100],
            textTheme: const TextTheme(
              headlineMedium:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              bodyMedium:
                  TextStyle(fontSize: 16, color: Colors.black54),
            ),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.black87,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              elevation: 4,
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.blueGrey,
            scaffoldBackgroundColor: Colors.grey[900],
            cardColor: Colors.grey[850],
            textTheme: const TextTheme(
              headlineMedium:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white70),
              bodyMedium:
                  TextStyle(fontSize: 16, color: Colors.white60),
            ),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white70,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              elevation: 4,
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
          ),
          themeMode: themeProvider.themeMode,
          home: appState.isFirstRun ? const OnboardingScreen() : const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const CalendarScreen(),
    const ReportScreen(),
    const NotesScreen(),
    const SettingsScreen(),
  ];

  final List<IconData> _icons = [
    Icons.home,
    Icons.calendar_today,
    Icons.analytics,
    Icons.note_alt,
    Icons.settings,
  ];

  final List<String> _labels = [
    'Inicio',
    'Calendario',
    'Informes',
    'Notas',
    'Ajustes',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _screens,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton(
              onPressed: () => _showQuickActionMenu(context),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBottomNavigationBar.builder(
        itemCount: _icons.length,
        tabBuilder: (int index, bool isActive) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isActive ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  _icons[index],
                  size: 24,
                  color: isActive
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[index],
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
            ],
          );
        },
        activeIndex: _currentIndex,
        gapLocation: GapLocation.none,
        notchSmoothness: NotchSmoothness.smoothEdge,
        leftCornerRadius: 16,
        rightCornerRadius: 16,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        },
        backgroundColor: Theme.of(context).cardColor,
        elevation: 8,
      ),
    );
  }

  void _showQuickActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Theme.of(context).cardColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.event, color: Colors.blueAccent),
                title: const Text('Nuevo Evento'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time, color: Colors.green),
                title: const Text('Registrar Horas'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_add, color: Colors.orange),
                title: const Text('Nueva Nota'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.analytics, color: Colors.purple),
                title: const Text('Ver Informe Rápido'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen()));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'title': 'Bienvenido a Smart Calendar',
      'description': 'Organiza tus eventos, horas predicadas y notas en un solo lugar.',
    },
    {
      'title': 'Explora el Calendario',
      'description': 'Añade eventos, registra horas y mueve tus planes fácilmente.',
    },
    {
      'title': 'Analiza tus Informes',
      'description': 'Sigue tus metas y exporta resúmenes detallados.',
    },
    {
      'title': 'Toma Notas Avanzadas',
      'description': 'Escribe, dibuja y organiza tus ideas con flexibilidad.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _onboardingData.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _onboardingData[index]['title']!,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _onboardingData[index]['description']!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _onboardingData.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                if (_currentPage < _onboardingData.length - 1) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_currentPage == _onboardingData.length - 1 ? 'Comenzar' : 'Siguiente'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
