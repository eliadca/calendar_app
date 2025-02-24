package com.example.calendar_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

class SmartCalendarWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // Obtiene la preferencia 'theme'
            val theme = widgetData.getString("theme", "system")
            val isDark = theme == "dark" ||
                (theme == "system" &&
                    (context.resources.configuration.uiMode and
                            android.content.res.Configuration.UI_MODE_NIGHT_MASK
                            ) == android.content.res.Configuration.UI_MODE_NIGHT_YES)

            // Fondo según tema
            views.setInt(
                R.id.widget_layout,
                "setBackgroundResource",
                if (isDark) android.R.color.black else android.R.color.white
            )

            // Sección: Horas
            val showHours = widgetData.getBoolean("showHours", true)
            views.setViewVisibility(
                R.id.hours_container,
                if (showHours) android.view.View.VISIBLE else android.view.View.GONE
            )

            if (showHours) {
                val weekHours = widgetData.getFloat("weekHours", 0f)
                val monthHours = widgetData.getFloat("monthHours", 0f)
                val monthGoal = widgetData.getFloat("monthGoal", 0f)
                views.setTextViewText(R.id.week_hours_text, "Semana: $weekHours h")
                views.setTextViewText(R.id.month_hours_text, "Mes: $monthHours h")

                // Evita valores negativos o raros si monthGoal es 0
                views.setProgressBar(
                    R.id.month_progress,
                    monthGoal.toInt().coerceAtLeast(1),
                    monthHours.toInt().coerceAtLeast(0),
                    false
                )
            }

            // Sección: Notas
            val showNotes = widgetData.getBoolean("showNotes", true)
            views.setViewVisibility(
                R.id.notes_container,
                if (showNotes) android.view.View.VISIBLE else android.view.View.GONE
            )

            if (showNotes) {
                val notesJson = widgetData.getString("notes", "[]") ?: "[]"
                // Eliminamos corchetes y convertimos en array separando por comas
                // Manejo de cadenas con comillas
                val notes = notesJson.removeSurrounding("[", "]").split(",").map { it.trim() }
                views.setTextViewText(R.id.note_1, notes.getOrNull(0)?.removeSurrounding("\"") ?: "")
                views.setTextViewText(R.id.note_2, notes.getOrNull(1)?.removeSurrounding("\"") ?: "")
                views.setTextViewText(R.id.note_3, notes.getOrNull(2)?.removeSurrounding("\"") ?: "")
            }

            // Sección: Eventos
            val showEvents = widgetData.getBoolean("showEvents", true)
            views.setViewVisibility(
                R.id.events_container,
                if (showEvents) android.view.View.VISIBLE else android.view.View.GONE
            )

            if (showEvents) {
                val eventsJson = widgetData.getString("events", "[]") ?: "[]"
                val events = eventsJson.removeSurrounding("[", "]").split(",").map { it.trim() }
                views.setTextViewText(R.id.event_1, events.getOrNull(0)?.removeSurrounding("\"") ?: "")
                views.setTextViewText(R.id.event_2, events.getOrNull(1)?.removeSurrounding("\"") ?: "")
                views.setTextViewText(R.id.event_3, events.getOrNull(2)?.removeSurrounding("\"") ?: "")
            }

            // Botones del Widget -> Se envían Broadcasts con URIs específicas
            val addHour1Intent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("com.example.calendar_app://widget/add_hour_1")
            )
            val addHour30MinIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("com.example.calendar_app://widget/add_hour_30min")
            )
            val addNoteIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("com.example.calendar_app://widget/add_note")
            )

            views.setOnClickPendingIntent(R.id.add_hour_1_button, addHour1Intent)
            views.setOnClickPendingIntent(R.id.add_hour_30min_button, addHour30MinIntent)
            views.setOnClickPendingIntent(R.id.add_note_button, addNoteIntent)

            // Actualiza el widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
