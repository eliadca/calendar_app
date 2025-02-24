import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_app/database_helper.dart';
import 'dart:async';

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._init();
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static const int _inactivityNotificationId = 9999;

  factory NotificationHelper() => _instance;

  NotificationHelper._init();

  static Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == 'snooze') {
          if (response.notificationId != null) {
            await _snoozeNotification(response.notificationId!);
          }
        } else if (response.actionId == 'open') {
          // Aquí podrías hacer que la app abra cierta pantalla
          print('Abrir notificación: ${response.payload}');
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'smart_calendar_channel',
      'Smart Calendar Notifications',
      description: 'Notificaciones para eventos, metas y notas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Programar chequeo de inactividad
    _scheduleInactivityCheck();
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? recurrence, // 'daily', 'weekly', 'monthly', null
    String? sound,
    String? payload,
    bool silent = false, // Modo silencioso
  }) async {
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final prefs = await SharedPreferences.getInstance();

    // Si silent es true, se desactiva vibración y sonido.
    final enableVibration = silent ? false : (prefs.getBool('notificationVibration') ?? true);
    final notificationSound = silent ? null : (sound ?? prefs.getString('notificationSound'));

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_calendar_channel',
      'Smart Calendar Notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      sound: notificationSound != null && notificationSound != 'default'
          ? RawResourceAndroidNotificationSound(notificationSound)
          : null,
      playSound: !silent,
      enableVibration: enableVibration,
      styleInformation: const BigTextStyleInformation(''),
      actions: [
        const AndroidNotificationAction('open', 'Abrir'),
        const AndroidNotificationAction('snooze', 'Posponer 10 min'),
      ],
    );

    // Aquí usamos la misma configuración para iOS/macOS si fuera necesario
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    if (recurrence == null) {
      // Notificación única
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tzScheduledTime,
        notificationDetails,
        androidAllowWhileIdle: true,
        payload: payload,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } else {
      // Notificación recurrente (daily, weekly, monthly)
      await _scheduleRecurringNotification(
        id: id,
        title: title,
        body: body,
        startTime: tzScheduledTime,
        recurrence: recurrence,
        notificationDetails: notificationDetails,
        silent: silent,
      );
    }
  }

  static Future<void> _scheduleRecurringNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime startTime,
    required String recurrence,
    required NotificationDetails notificationDetails,
    bool silent = false,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    // Definimos el intervalo en función de la recurrencia
    final Duration interval;
    switch (recurrence) {
      case 'daily':
        interval = const Duration(days: 1);
        break;
      case 'weekly':
        interval = const Duration(days: 7);
        break;
      case 'monthly':
        // Aproximación de 30 días
        interval = const Duration(days: 30);
        break;
      default:
        return;
    }

    // Programamos por ejemplo 12 notificaciones (un año de mensual, 12 semanas, etc.)
    for (int i = 0; i < 12; i++) {
      final scheduledTime = startTime.add(interval * i);
      if (scheduledTime.isAfter(now)) {
        await _notifications.zonedSchedule(
          id + i,
          title,
          body,
          scheduledTime,
          notificationDetails,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  static Future<void> _snoozeNotification(int id) async {
    // Buscamos la notificación pendiente con ese ID
    final pending = await _notifications.pendingNotificationRequests();
    final notification = pending.firstWhere(
      (n) => n.id == id,
      orElse: () => PendingNotificationRequest(
        // Ajuste: el constructor de PendingNotificationRequest no usa parámetros con nombre
        id,
        '',
        '',
        null,
      ),
    );

    // Cancelamos la notificación actual y la reprogramamos 10 minutos después
    if (notification.title != null) {
      await _notifications.cancel(id);
      final newTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
      await scheduleNotification(
        id: id,
        title: notification.title!,
        body: notification.body ?? '',
        scheduledTime: newTime,
      );
    }
  }

  static Future<void> showInstantNotification({
    required String title,
    required String body,
    String? sound,
    bool silent = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Manejamos la vibración y sonido
    final enableVibration = silent ? false : (prefs.getBool('notificationVibration') ?? true);
    final notificationSound = silent ? null : (sound ?? prefs.getString('notificationSound'));

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_calendar_channel',
      'Smart Calendar Notifications',
      importance: Importance.max,
      priority: Priority.high,
      sound: notificationSound != null && notificationSound != 'default'
          ? RawResourceAndroidNotificationSound(notificationSound)
          : null,
      playSound: !silent,
      enableVibration: enableVibration,
    );

    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  static Future<void> checkGoalNotification(int year, double currentHours) async {
    final db = DatabaseHelper.instance;
    final goal = await db.getGoal(year);
    final monthlyGoal = goal / 12;
    final percentage = currentHours / monthlyGoal;
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('language') ?? 'es';

    // Evitar null en getBool
    final notified50 = prefs.getBool('notified_50_$year') ?? false;
    final notified75 = prefs.getBool('notified_75_$year') ?? false;

    // 50% de la meta
    if (percentage >= 0.5 && percentage < 0.75 && !notified50) {
      await showInstantNotification(
        title: language == 'es' ? '¡50% de tu meta mensual!' : '50% of your monthly goal!',
        body: language == 'es'
            ? 'Has alcanzado el ${ (percentage * 100).toStringAsFixed(0) }% de tu meta de $monthlyGoal horas este mes.'
            : 'You’ve reached ${ (percentage * 100).toStringAsFixed(0) }% of your $monthlyGoal hours goal this month.',
        sound: 'alert',
      );
      await prefs.setBool('notified_50_$year', true);
    }
    // 75% de la meta
    else if (percentage >= 0.75 && percentage < 1.0 && !notified75) {
      await showInstantNotification(
        title: language == 'es' ? '¡75% de tu meta mensual!' : '75% of your monthly goal!',
        body: language == 'es'
            ? 'Has alcanzado el ${ (percentage * 100).toStringAsFixed(0) }% de tu meta de $monthlyGoal horas este mes.'
            : 'You’ve reached ${ (percentage * 100).toStringAsFixed(0) }% of your $monthlyGoal hours goal this month.',
        sound: 'alert',
      );
      await prefs.setBool('notified_75_$year', true);
    }
  }

  static Future<void> _scheduleInactivityCheck() async {
    // Revisa inactividad una vez al día
    Timer.periodic(const Duration(days: 1), (timer) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final lastWeek = now.subtract(const Duration(days: 7));
      final recentEvents = await db.getEventsByPeriod(lastWeek, now);

      final prefs = await SharedPreferences.getInstance();
      final language = prefs.getString('language') ?? 'es';
      // Evitamos null
      final wasNotified = prefs.getBool('inactivity_notified_$now') ?? false;

      if (recentEvents.isEmpty && !wasNotified) {
        await showInstantNotification(
          title: language == 'es' ? '¡Sin actividad reciente!' : 'No recent activity!',
          body: language == 'es'
              ? 'No has registrado horas en los últimos 7 días.'
              : 'You haven’t logged any hours in the last 7 days.',
        );
        await prefs.setBool('inactivity_notified_$now', true);
      }
    });
  }

  static Future<void> scheduleSilentReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      silent: true,
    );
  }
}
