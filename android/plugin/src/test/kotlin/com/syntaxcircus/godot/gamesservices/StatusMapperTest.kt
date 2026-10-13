package com.syntaxcircus.godot.gamesservices

import java.io.IOException
import java.net.UnknownHostException
import org.junit.Assert.assertEquals
import org.junit.Test

class StatusMapperTest {
    // The mapper takes the SDK's category sets as parameters, so these numbers only need to be distinct.
    private val mapper = StatusMapper(
        signedOutCodes = setOf(4, 6, 16),
        networkCodes = setOf(7, 15, 17, 26503, 26504, 26505, 26506),
    )

    @Test
    fun successIsCompleted() {
        assertEquals(StatusMapper.COMPLETED, mapper.fromStatusCode(0))
    }

    @Test
    fun signInRequiredAndCancelledAreSignedOut() {
        assertEquals(StatusMapper.SIGNED_OUT, mapper.fromStatusCode(4))
        assertEquals(StatusMapper.SIGNED_OUT, mapper.fromStatusCode(6))
        assertEquals(StatusMapper.SIGNED_OUT, mapper.fromStatusCode(16))
    }

    @Test
    fun networkProblemsAreUnavailableSoTheCallerKeepsAndRetries() {
        for (code in listOf(7, 15, 17, 26503, 26504, 26505, 26506)) {
            assertEquals("code $code", StatusMapper.UNAVAILABLE, mapper.fromStatusCode(code))
        }
    }

    @Test
    fun configurationAndUnknownErrorsAreFailedNotRetriedForever() {
        assertEquals(StatusMapper.FAILED, mapper.fromStatusCode(10)) // DEVELOPER_ERROR
        assertEquals(StatusMapper.FAILED, mapper.fromStatusCode(13)) // ERROR
        assertEquals(StatusMapper.FAILED, mapper.fromStatusCode(99999))
    }

    @Test
    fun anExceptionWithAStatusCodeUsesIt() {
        assertEquals(StatusMapper.UNAVAILABLE, mapper.fromThrowable(RuntimeException("x"), 7))
        assertEquals(StatusMapper.SIGNED_OUT, mapper.fromThrowable(RuntimeException("x"), 4))
    }

    @Test
    fun anIoFailureWithoutAStatusCodeIsUnavailable() {
        assertEquals(StatusMapper.UNAVAILABLE, mapper.fromThrowable(IOException("down"), null))
        assertEquals(StatusMapper.UNAVAILABLE, mapper.fromThrowable(UnknownHostException("host"), null))
    }

    @Test
    fun anythingElseIsFailed() {
        assertEquals(StatusMapper.FAILED, mapper.fromThrowable(IllegalStateException("boom"), null))
        assertEquals(StatusMapper.FAILED, mapper.fromThrowable(NullPointerException(), null))
    }

    @Test
    fun theCodesAreExactlyTheInterfaceStrings() {
        assertEquals("completed", StatusMapper.COMPLETED)
        assertEquals("signed_out", StatusMapper.SIGNED_OUT)
        assertEquals("unavailable", StatusMapper.UNAVAILABLE)
        assertEquals("failed", StatusMapper.FAILED)
    }
}
