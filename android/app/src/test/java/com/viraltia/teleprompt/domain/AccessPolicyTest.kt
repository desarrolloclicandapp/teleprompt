package com.viraltia.teleprompt.domain

import org.junit.Assert.*
import org.junit.Test

class AccessPolicyTest {
    private val start = 1_800_000_000_000L

    @Test fun trialRequiresExplicitActivation() {
        assertEquals(AccessState.NOT_STARTED, AccessPolicy.state(null, start, false))
    }
    @Test fun exactlySevenDaysNotCalendarBoundaries() {
        assertEquals(604_800_000L, AccessPolicy.TRIAL_MILLIS)
        assertEquals(AccessState.ACTIVE, AccessPolicy.state(start, start + AccessPolicy.TRIAL_MILLIS - 1, false))
        assertEquals(AccessState.EXPIRED, AccessPolicy.state(start, start + AccessPolicy.TRIAL_MILLIS, false))
    }
    @Test fun remainingDaysRoundUpAndStopAtExpiry() {
        assertEquals(7, AccessPolicy.daysLeft(start, start))
        assertEquals(1, AccessPolicy.daysLeft(start, start + AccessPolicy.TRIAL_MILLIS - 1))
        assertEquals(0, AccessPolicy.daysLeft(start, start + AccessPolicy.TRIAL_MILLIS))
        assertEquals(0, AccessPolicy.daysLeft(null, start))
    }
    @Test fun clockBeforeActivationDoesNotGrantExtraTime() {
        assertEquals(AccessState.EXPIRED, AccessPolicy.state(start, start - 1, false))
        assertEquals(0, AccessPolicy.daysLeft(start, start - 1))
    }
    @Test fun lifetimeDominatesEveryTrialState() {
        for (trialStart in listOf(null, start)) {
            assertEquals(AccessState.LIFETIME, AccessPolicy.state(trialStart, start, true))
            assertEquals(AccessState.LIFETIME, AccessPolicy.state(trialStart, start + AccessPolicy.TRIAL_MILLIS * 2, true))
        }
    }
}
