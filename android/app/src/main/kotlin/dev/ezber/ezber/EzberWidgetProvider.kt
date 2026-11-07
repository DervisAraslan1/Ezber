package dev.ezber.ezber

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.TimeZone

class EzberWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val forecast = widgetData.getString("forecast", null)
            ?.split(",")?.mapNotNull { it.toIntOrNull() }.orEmpty()
        // The app sends two weeks of counts, so the number stays right on days
        // it is not opened.
        val index = studyDay() - widgetData.getInt("firstDay", 0).toLong()
        val waiting = forecast.getOrNull(index.toInt())
        val streak = widgetData.getInt("streak", 0)

        val views = RemoteViews(context.packageName, R.layout.ezber_widget).apply {
            setTextViewText(
                R.id.widget_title,
                if (streak > 0) "Ezber · $streak gün" else "Ezber",
            )
            setTextViewText(
                R.id.widget_count,
                when {
                    waiting == null -> "Başlamaya hazır"
                    waiting > 0 -> "$waiting kelime bekliyor"
                    else -> "Bugünlük tamam"
                },
            )
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("ezber://ac"),
                ),
            )
        }
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    /** Days since 1970 of the study day, which ends at 04:00 like the app's. */
    private fun studyDay(): Long {
        val now = System.currentTimeMillis()
        val local = now + TimeZone.getDefault().getOffset(now) - 4 * 3_600_000L
        return Math.floorDiv(local, 86_400_000L)
    }
}
