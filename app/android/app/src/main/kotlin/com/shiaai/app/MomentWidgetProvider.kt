package com.shiaai.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.io.File
import kotlin.random.Random

/** A genuinely useful Android launcher widget; refreshes on the platform's
 * hourly AppWidget schedule and can also be advanced with its refresh button.
 *
 * The plate is cut for the cell the launcher gives it: a tall cell shows the
 * verse, its reference, the next prayer and the Hijri date, while a short one
 * shows the verse alone. Both layouts carry the same view ids, so the same
 * update fills either of them.
 *
 * The line itself is fetched from the installed Quran and Ghurar al-Hikam
 * databases (and from the cache the app writes after it has opened them).
 * Built-in lines are only the last resort, for a phone that has not downloaded
 * either book yet. */
class MomentWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it, hourly = true) }
    }

    /** The reader dragged the widget to a new size: re-cut the plate for the
     * new cell at once, instead of leaving the old layout squeezed (and its
     * text cut) until the next scheduled update. The hour's line itself is
     * kept — a resize must never change what the widget says. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, id, newOptions)
        updateOne(context, manager, id, hourly = true)
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
        val compact = (minHeight in 1 until 110) || (minHeight == 0 && minWidth in 1 until 180)

        val moments = loadMoments(context)
        val seed = if (hourly) System.currentTimeMillis() / HOUR_MS + id * 31L else System.nanoTime()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val key = "quote_$id"
        val seedKey = "seed_$id"
        val previous = prefs.getInt(key, -1)
        // Within one hour the line is stable — resize callbacks and the
        // platform's own re-deliveries re-use the stored text instead of
        // rolling again (the moments list itself comes back in random order
        // from SQLite, so an index alone would not be stable).
        var quote: Moment? = null
        if (hourly && prefs.getLong(seedKey, Long.MIN_VALUE) == seed) {
            val stored = prefs.getString("text_$id", null)
            if (!stored.isNullOrBlank()) {
                quote = Moment(stored, prefs.getString("ref_$id", "") ?: "")
            }
        }
        if (quote == null) {
            var selected = Random(seed.toInt()).nextInt(moments.size)
            if (selected == previous) selected = (selected + 1) % moments.size
            quote = moments[selected]
            prefs.edit()
                .putInt(key, selected)
                .putLong(seedKey, seed)
                .putString("text_$id", quote.text)
                .putString("ref_$id", quote.reference)
                .apply()
        }

        // The next prayer and the Hijri date, as the app itself calculates
        // them. The widget reads them from the app's own preferences, so the
        // plate on the home screen never disagrees with the card in the app.
        val shared = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val nextPrayer = shared.getString("$FLUTTER_PREFIX$KEY_NEXT_PRAYER", null)
        val hijri = shared.getString("$FLUTTER_PREFIX$KEY_HIJRI", null)
        val line: Moment = quote ?: moments.first()

        // Android 12 and later can hold several plates and switch between
        // them by itself the moment the widget is resized — the surest way
        // for the content to adjust instead of being cut. Older launchers
        // take the single plate for the current cell and rely on
        // onAppWidgetOptionsChanged above.
        val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            RemoteViews(
                mapOf(
                    SizeF(110f, 70f) to buildViews(context, true, id, line, nextPrayer, hijri),
                    SizeF(180f, 110f) to buildViews(context, false, id, line, nextPrayer, hijri),
                )
            )
        } else {
            buildViews(context, compact, id, line, nextPrayer, hijri)
        }
        manager.updateAppWidget(id, views)
    }

    /** One filled plate. A short line is set large, a long one smaller —
     * still comfortably readable — so the words fit the cell instead of
     * being clipped at a fixed size. */
    private fun buildViews(
        context: Context,
        compact: Boolean,
        id: Int,
        quote: Moment,
        nextPrayer: String?,
        hijri: String?,
    ): RemoteViews {
        val views = RemoteViews(
            context.packageName,
            if (compact) R.layout.moment_widget_small else R.layout.moment_widget,
        )
        views.setTextViewText(R.id.moment_text, quote.text)
        views.setTextViewTextSize(
            R.id.moment_text,
            TypedValue.COMPLEX_UNIT_SP,
            textSizeSp(quote.text, compact),
        )
        views.setTextViewText(R.id.moment_reference, quote.reference)
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
        return views
    }

    /** Type size for the line itself: the shorter the ayat/hadith, the
     * larger it may stand; a long one steps down a size at a time and never
     * below a readable 11.5sp. */
    private fun textSizeSp(text: String, compact: Boolean): Float {
        val length = text.length
        return if (compact) {
            when {
                length <= 45 -> 16f
                length <= 90 -> 14f
                length <= 150 -> 12.5f
                else -> 11.5f
            }
        } else {
            when {
                length <= 45 -> 20f
                length <= 90 -> 17f
                length <= 150 -> 15f
                length <= 210 -> 13.5f
                else -> 12.5f
            }
        }
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
        private fun loadMoments(context: Context): List<Moment> {
            val live = ArrayList<Moment>(24)
            live += queryQuran(databaseFile(context, "quran.db"))
            live += queryGhurar(databaseFile(context, "hakam.db"))
            if (live.isNotEmpty()) return live
            val cached = loadCached(context)
            if (cached.isNotEmpty()) return cached
            return fallbackMoments
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

        private fun queryQuran(file: File?): List<Moment> {
            if (file == null) return emptyList()
            val sql = """
                SELECT q.tr, q.Arabic, q.verse, q.chapter, COALESCE(cp.Name, '')
                FROM Quran AS q
                LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
                WHERE LENGTH(COALESCE(q.tr, '')) BETWEEN 12 AND 240
                  AND LENGTH(COALESCE(q.Arabic, '')) BETWEEN 6 AND 220
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

        private fun queryGhurar(file: File?): List<Moment> {
            if (file == null) return emptyList()
            val sql = """
                SELECT p.mean, p.txt, COALESCE(s.title, '')
                FROM Parags AS p
                LEFT JOIN Sections AS s ON s.Secid = p.Secid
                WHERE LENGTH(COALESCE(p.mean, '')) BETWEEN 12 AND 240
                  AND LENGTH(COALESCE(p.txt, '')) BETWEEN 6 AND 260
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
