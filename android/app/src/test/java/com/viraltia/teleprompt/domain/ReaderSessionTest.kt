package com.viraltia.teleprompt.domain

import com.viraltia.teleprompt.ui.reader.ReaderSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ReaderSessionTest {
    @After fun resetMain() { Dispatchers.resetMain() }

    @Test fun firstPlayCountsInButResumeIsImmediate() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val session = ReaderSession()
        session.toggle(); runCurrent()
        assertEquals(3, session.countdown); assertFalse(session.playing)
        advanceTimeBy(3000); runCurrent()
        assertTrue(session.playing); assertEquals(0, session.countdown)
        session.pause(); session.toggle()
        assertTrue(session.playing); assertEquals(0, session.countdown)
        session.reset()
    }

    @Test fun resetCancelsCountdownAndOldTaskCannotRestartReading() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val session = ReaderSession()
        session.toggle(); runCurrent(); advanceTimeBy(1000)
        session.offsetPixels = 200f; session.reset()
        advanceTimeBy(5000); runCurrent()
        assertFalse(session.playing); assertFalse(session.hasStarted)
        assertEquals(0, session.countdown); assertEquals(0f, session.offsetPixels)
    }

    @Test fun remotePlayStartsWithoutCountdown() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val session = ReaderSession()
        session.toggle(remote = true)
        assertTrue(session.playing); assertEquals(0, session.countdown)
        session.reset()
    }
}
