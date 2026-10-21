package com.viraltia.teleprompt.domain

import kotlin.math.ceil

enum class AccessState { NOT_STARTED, ACTIVE, EXPIRED, LIFETIME }

object AccessPolicy {
    const val TRIAL_MILLIS = 7L * 24 * 60 * 60 * 1000

    fun state(startedAt: Long?, now: Long, lifetime: Boolean): AccessState = when {
        lifetime -> AccessState.LIFETIME
        startedAt == null -> AccessState.NOT_STARTED
        now >= startedAt && now - startedAt < TRIAL_MILLIS -> AccessState.ACTIVE
        else -> AccessState.EXPIRED
    }

    fun daysLeft(startedAt: Long?, now: Long): Int {
        if (startedAt == null || now < startedAt) return 0
        val elapsed = now - startedAt
        if (elapsed >= TRIAL_MILLIS) return 0
        return ceil((TRIAL_MILLIS - elapsed) / 86_400_000.0).toInt()
    }
}
