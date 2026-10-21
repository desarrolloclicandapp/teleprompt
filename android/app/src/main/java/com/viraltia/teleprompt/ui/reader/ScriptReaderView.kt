package com.viraltia.teleprompt.ui.reader

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import com.viraltia.teleprompt.data.ReaderPreferences
import com.viraltia.teleprompt.domain.ReaderMotion
import kotlin.math.abs

/** Layout is measured only when text/font/width changes, never per frame.
 * Layout.draw respects the canvas clip so long scripts do not need huge textures.
 */
class ScriptReaderView(context: Context) : View(context), Choreographer.FrameCallback {
    private val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private var text = ""
    private var prefs = ReaderPreferences()
    private var layout: StaticLayout? = null
    private var effectiveFontDp = 26f
    private var topPadding = 44f
    private var bottomPadding = 160f
    private var horizontalPadding = 24f
    private var offset = 0f
    private var maxOffset = 0f
    private var running = false
    private var active = true
    private var attached = false
    private var scheduled = false
    private var previousFrame = 0L
    private var previousReport = 0L
    private var touchY = 0f
    private var moved = false
    var onPosition: (Float, Float) -> Unit = { _, _ -> }
    var onTapped: () -> Unit = {}

    fun configure(value: String, preferences: ReaderPreferences) {
        val needsLayout = text != value || prefs.fontSize != preferences.fontSize
        text = value; prefs = preferences
        scaleX = if (prefs.horizontal) -1f else 1f
        scaleY = if (prefs.vertical) -1f else 1f
        if (needsLayout) rebuild()
    }

    fun setPlaying(value: Boolean) {
        running = value
        if (!value) stopFrames() else schedule()
    }
    fun setActive(value: Boolean) { active = value; if (value) schedule() else stopFrames() }
    fun reset() { offset = 0f; report(); invalidate() }
    fun restoreOffset(value: Float) { offset = value.coerceIn(0f, maxOffset); report(); invalidate() }
    fun step(amount: Float) { offset = (offset + amount).coerceIn(0f, maxOffset); report(); invalidate() }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); attached = true; schedule() }
    override fun onDetachedFromWindow() { attached = false; stopFrames(); super.onDetachedFromWindow() }
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) { rebuild() }

    private fun rebuild() {
        if (width <= 0 || height <= 0) return
        val density = resources.displayMetrics.density
        effectiveFontDp = (prefs.fontSize * (width / density) / 380f).coerceIn(16f, 82f)
        paint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, effectiveFontDp, resources.displayMetrics)
        horizontalPadding = minOf(26f * density, width * .08f)
        topPadding = maxOf(44f * density, height * .12f)
        bottomPadding = maxOf(160f * density, height * .55f)
        layout = StaticLayout.Builder.obtain(text, 0, text.length, paint,
            (width - horizontalPadding * 2).toInt().coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setIncludePad(false)
            .setLineSpacing(maxOf(4f * density, paint.textSize * .18f), 1f)
            .build()
        maxOffset = ((layout?.height ?: 0) + topPadding + bottomPadding - height).coerceAtLeast(0f)
        offset = offset.coerceIn(0f, maxOffset)
        report(); invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.clipRect(0, 0, width, height)
        canvas.translate(horizontalPadding, topPadding - offset)
        layout?.draw(canvas)
        canvas.restore()
    }

    private fun schedule() {
        if (attached && active && running && !scheduled) {
            scheduled = true; Choreographer.getInstance().postFrameCallback(this)
        }
    }
    private fun stopFrames() {
        Choreographer.getInstance().removeFrameCallback(this)
        scheduled = false; previousFrame = 0L
    }
    override fun doFrame(frameTimeNanos: Long) {
        scheduled = false
        if (!active || !running || !attached) { previousFrame = 0L; return }
        if (previousFrame != 0L) {
            val seconds = (frameTimeNanos - previousFrame) / 1_000_000_000.0
            val delta = ReaderMotion.distance(ReaderMotion.speed(prefs.level), effectiveFontDp / 42.0, seconds)
            offset = (offset + delta.toFloat() * resources.displayMetrics.density).coerceIn(0f, maxOffset)
            invalidate()
        }
        previousFrame = frameTimeNanos
        // Persist in-memory position and refresh controls at most ~8 times/sec.
        if (frameTimeNanos - previousReport > 120_000_000) { report(); previousReport = frameTimeNanos }
        schedule()
    }
    private fun report() { onPosition(offset, if (maxOffset > 0) offset / maxOffset else 0f) }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { touchY = event.y; moved = false; parent?.requestDisallowInterceptTouchEvent(true); return true }
            MotionEvent.ACTION_MOVE -> {
                val delta = touchY - event.y
                if (abs(delta) > 2) moved = true
                step(delta); touchY = event.y; return true
            }
            MotionEvent.ACTION_UP -> { parent?.requestDisallowInterceptTouchEvent(false); if (!moved) performClick(); return true }
            MotionEvent.ACTION_CANCEL -> { parent?.requestDisallowInterceptTouchEvent(false); return true }
        }
        return super.onTouchEvent(event)
    }
    override fun performClick(): Boolean { super.performClick(); onTapped(); return true }
}
