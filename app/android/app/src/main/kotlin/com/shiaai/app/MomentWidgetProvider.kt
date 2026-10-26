package com.shiaai.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.io.File
import kotlin.random.Random

/** A genuinely useful Android launcher widget; refreshes on the platform's
 * hourly AppWidget schedule and can also be advanced with its refresh button.
 *
 * The plate is cut for the cell the launcher gives it: a compact cell keeps a
 * shorter quote, its source, and the refresh button; a taller cell also shows
 * the next prayer and Hijri date. Resizing triggers a fresh layout selection,
 * and both layouts carry the same view ids.
 *
 * The line itself is fetched from the installed Quran and Ghurar al-Hikam
 * databases (and from the cache the app writes after it has opened them).
 * Built-in lines are only the last resort, for a phone that has not downloaded
 * either book yet. */
class MomentWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it, hourly = true) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
        // Re-select the compact/full RemoteViews immediately after a resize;
        // otherwise launchers keep showing a layout sized for the old bounds.
        updateOne(context, manager, appWidgetId, hourly = false)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_REFRESH) return
        refreshAll(context)
    }

    private fun updateOne(context: Context, manager: AppWidgetManager, id: Int, hourly: Boolean) {
        // The launcher tells the widget how much room it has. A cell shorter
        // than a full row of text gets the compact plate.
        val options = manager.getAppWidgetOptions(id)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val compact = (minHeight in 1 until 160) || (minWidth in 1 until 210)
        val views = RemoteViews(
            context.packageName,
            if (compact) R.layout.moment_widget_small else R.layout.moment_widget,
        )
        val moments = loadMoments(context, compact)
        val seed = if (hourly) System.currentTimeMillis() / HOUR_MS + id * 31L else System.nanoTime()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val key = "quote_$id"
        val previous = prefs.getInt(key, -1)
        var selected = Random(seed.toInt()).nextInt(moments.size)
        if (selected == previous) selected = (selected + 1) % moments.size
        prefs.edit().putInt(key, selected).apply()
        val quote = moments[selected]
        views.setTextViewText(R.id.moment_text, quote.text)
        views.setTextViewText(R.id.moment_reference, quote.reference)
        views.setTextViewTextSize(
            R.id.moment_text,
            TypedValue.COMPLEX_UNIT_SP,
            quoteTextSizeSp(quote.text.length, compact),
        )

        // The next prayer and the Hijri date, as the app itself calculates
        // them. The widget reads them from the app's own preferences, so the
        // plate on the home screen never disagrees with the card in the app.
        val shared = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val nextPrayer = shared.getString("$FLUTTER_PREFIX$KEY_NEXT_PRAYER", null)
        val hijri = shared.getString("$FLUTTER_PREFIX$KEY_HIJRI", null)
        views.setTextViewText(R.id.moment_next_prayer, nextPrayer ?: "")
        views.setTextViewText(R.id.moment_hijri, hijri ?: "")
        views.setViewVisibility(
            R.id.moment_next_prayer,
            if (compact || nextPrayer.isNullOrEmpty()) View.GONE else View.VISIBLE,
        )
        views.setViewVisibility(
            R.id.moment_hijri,
            if (compact || hijri.isNullOrEmpty()) View.GONE else View.VISIBLE,
        )

        val refreshIntent = Intent(context, MomentWidgetProvider::class.java).apply { action = ACTION_REFRESH }
        views.setOnClickPendingIntent(
            R.id.moment_refresh,
            PendingIntent.getBroadcast(context, id, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        )
        val openIntent = Intent(context, MainActivity::class.java)
        views.setOnClickPendingIntent(
            R.id.moment_root,
            PendingIntent.getActivity(context, id + 1000, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        )
        manager.updateAppWidget(id, views)
    }

    private fun quoteTextSizeSp(length: Int, compact: Boolean): Float = when {
        compact && length >= 55 -> 12.5f
        compact && length >= 35 -> 13.5f
        compact -> 15f
        length >= 105 -> 13.5f
        length >= 70 -> 15f
        else -> 17f
    }

    private data class Moment(val text: String, val reference: String)

    companion object {
        private const val ACTION_REFRESH = "com.shiaai.app.ACTION_REFRESH_MOMENT"
        private const val PREFS_NAME = "moment_widget"
        private const val HOUR_MS = 60L * 60L * 1000L

        /** Where the Flutter client keeps its own preferences, and the prefix
         * it puts on every key inside them. */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_PREFIX = "flutter."
        private const val KEY_NEXT_PRAYER = "widget_next_prayer"
        private const val KEY_HIJRI = "widget_hijri"
        private const val KEY_MOMENTS = "widget_moments"
        private const val KEY_DB_DIR = "widget_db_dir"

        /** Asked by the app after it has written a fresh batch of lines. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MomentWidgetProvider::class.java))
            val provider = MomentWidgetProvider()
            ids.forEach { provider.updateOne(context, manager, it, hourly = false) }
        }

        /** Quran first, then Ghurar al-Hikam. The app's cache fills any gap
         * (a database the widget could not open). Built-in lines are last. */
        private fun loadMoments(context: Context, compact: Boolean): List<Moment> {
            // A compact plate receives shorter source lines; the full widget
            // can show longer ayat/hadith with a proportionally smaller font.
            val maxCharacters = if (compact) 70 else 140
            val live = ArrayList<Moment>(24)
            live += queryQuran(databaseFile(context, "quran.db"), maxCharacters)
            live += queryGhurar(databaseFile(context, "hakam.db"), maxCharacters)
            if (live.isNotEmpty()) return live
            val cached = loadCached(context).filter { it.text.length <= maxCharacters }
            if (cached.isNotEmpty()) return cached
            return fallbackMoments.filter { it.text.length <= maxCharacters }.ifEmpty { fallbackMoments }
        }

        private fun databaseFile(context: Context, name: String): File? {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val hinted = prefs.getString("$FLUTTER_PREFIX$KEY_DB_DIR", null)
            val databases = context.getDatabasePath("shia_library").parentFile
            val candidates = listOfNotNull(
                hinted?.let { File(it, name) },
                databases?.let { File(File(it, "shia_library"), name) },
                File(File(context.applicationInfo.dataDir, "databases/shia_library"), name),
                File(File(context.applicationInfo.dataDir, "app_flutter/shia_library"), name),
            )
            return candidates.firstOrNull { it.isFile && it.length() > 1024L }
        }

        private fun queryQuran(file: File?, maxCharacters: Int): List<Moment> {
            if (file == null) return emptyList()
            val sql = """
                SELECT q.tr, q.Arabic, q.verse, q.chapter, COALESCE(cp.Name, '')
                FROM Quran AS q
                LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
                WHERE LENGTH(COALESCE(q.tr, '')) BETWEEN 12 AND $maxCharacters
                  AND LENGTH(COALESCE(q.Arabic, '')) BETWEEN 6 AND ${maxCharacters + 20}
                ORDER BY RANDOM() LIMIT 12
            """.trimIndent()
            return query(file, sql) { cursor ->
                val urdu = cursor.getString(0)?.trim().orEmpty()
                val arabic = cursor.getString(1)?.trim().orEmpty()
                val verse = cursor.getInt(2)
                val chapter = cursor.getInt(3)
                val arabicName = cursor.getString(4)?.trim().orEmpty()
                val name = if (chapter in 1..URDU_SURAHS.size) URDU_SURAHS[chapter - 1] else arabicName
                val text = urdu.ifBlank { arabic }
                if (text.length < 8) null
                else Moment(text, if (name.isBlank()) "قرآنِ کریم" else "قرآنِ کریم — سورہ $name، آیت $verse")
            }
        }

        private fun queryGhurar(file: File?, maxCharacters: Int): List<Moment> {
            if (file == null) return emptyList()
            val sql = """
                SELECT p.mean, p.txt, COALESCE(s.title, '')
                FROM Parags AS p
                LEFT JOIN Sections AS s ON s.Secid = p.Secid
                WHERE LENGTH(COALESCE(p.mean, '')) BETWEEN 12 AND $maxCharacters
                  AND LENGTH(COALESCE(p.txt, '')) BETWEEN 6 AND ${maxCharacters + 20}
                ORDER BY RANDOM() LIMIT 12
            """.trimIndent()
            return query(file, sql) { cursor ->
                val urdu = cursor.getString(0)?.trim().orEmpty()
                val arabic = cursor.getString(1)?.trim().orEmpty()
                val section = cursor.getString(2)?.trim().orEmpty()
                val text = urdu.ifBlank { arabic }
                if (text.length < 8) null
                else Moment(
                    text,
                    if (section.isBlank()) "غرر الحکم" else "غرر الحکم — $section",
                )
            }
        }

        private fun query(
            file: File,
            sql: String,
            map: (android.database.Cursor) -> Moment?,
        ): List<Moment> {
            var database: SQLiteDatabase? = null
            var cursor: android.database.Cursor? = null
            return try {
                database = SQLiteDatabase.openDatabase(
                    file.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY,
                )
                cursor = database.rawQuery(sql, null)
                val found = ArrayList<Moment>(12)
                while (cursor.moveToNext()) {
                    val moment = map(cursor) ?: continue
                    found += moment
                }
                found
            } catch (_: Exception) {
                emptyList()
            } finally {
                cursor?.close()
                database?.close()
            }
        }

        private fun loadCached(context: Context): List<Moment> {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString("$FLUTTER_PREFIX$KEY_MOMENTS", null) ?: return emptyList()
            return try {
                val array = JSONArray(raw)
                buildList {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val text = item.optString("text").trim()
                        val reference = item.optString("reference").trim()
                        if (text.isEmpty()) continue
                        add(Moment(text, reference.ifBlank { item.optString("kind") }))
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        // Shown only while neither book has been downloaded. Once quran.db or
        // hakam.db is on the device the plate uses those, not these lines.
        private val fallbackMoments = listOf(
            Moment("بے شک اللہ صبر کرنے والوں کے ساتھ ہے۔", "قرآنِ کریم — البقرہ ۲:۱۵۳"),
            Moment("اور تمہارا رب فرماتا ہے: مجھ سے دعا کرو، میں قبول کروں گا۔", "قرآنِ کریم — غافر ۴۰:۶۰"),
            Moment("اللہ کے ذکر سے دل اطمینان پاتے ہیں۔", "قرآنِ کریم — الرعد ۱۳:۲۸"),
            Moment("نیکی اور تقویٰ کے کاموں میں ایک دوسرے کی مدد کرو۔", "قرآنِ کریم — المائدہ ۵:۲"),
            Moment("اور جو اللہ پر بھروسا کرے تو وہ اس کے لیے کافی ہے۔", "قرآنِ کریم — الطلاق ۶۵:۳"),
            Moment("بے شک مشکل کے ساتھ آسانی ہے۔", "قرآنِ کریم — الشرح ۹۴:۶"),
            Moment("علم مال سے بہتر ہے، کیونکہ علم تیری حفاظت کرتا ہے اور مال کی حفاظت تجھے کرنی پڑتی ہے۔", "غرر الحکم"),
            Moment("جو اپنے نفس کا محاسبہ کرتا ہے وہ نفع میں رہتا ہے، اور جو غافل رہتا ہے وہ نقصان میں۔", "غرر الحکم"),
        )

        private val URDU_SURAHS = listOf(
            "الفاتحہ", "البقرہ", "آل عمران", "النساء", "المائدہ", "الانعام", "الاعراف", "الانفال",
            "التوبہ", "یونس", "ہود", "یوسف", "الرعد", "ابراہیم", "الحجر", "النحل", "بنی اسرائیل",
            "الکہف", "مریم", "طٰہٰ", "الانبیاء", "الحج", "المؤمنون", "النور", "الفرقان", "الشعراء",
            "النمل", "القصص", "العنکبوت", "الروم", "لقمان", "السجدہ", "الاحزاب", "سبا", "فاطر",
            "یٰس", "الصافات", "ص", "الزمر", "المؤمن", "حم السجدہ", "الشوری", "الزخرف", "الدخان",
            "الجاثیہ", "الاحقاف", "محمد", "الفتح", "الحجرات", "ق", "الذاریات", "الطور", "النجم",
            "القمر", "الرحمن", "الواقعہ", "الحدید", "المجادلہ", "الحشر", "الممتحنہ", "الصف", "الجمعہ",
            "المنافقون", "التغابن", "الطلاق", "التحریم", "الملک", "القلم", "الحاقہ", "المعارج",
            "نوح", "الجن", "المزمل", "المدثر", "القیامہ", "الانسان", "المرسلات", "النبا", "النازعات",
            "عبس", "التکویر", "الانفطار", "المطففین", "الانشقاق", "البروج", "الطارق", "الاعلی",
            "الغاشیہ", "الفجر", "البلد", "الشمس", "اللیل", "الضحی", "الم نشرح", "التین", "العلق",
            "القدر", "البینہ", "الزلزلہ", "العادیات", "القارعہ", "التکاثر", "العصر", "الہمزہ",
            "الفیل", "قریش", "الماعون", "الکوثر", "الکافرون", "النصر", "لہب", "الاخلاص", "الفلق", "الناس",
        )
    }
}
