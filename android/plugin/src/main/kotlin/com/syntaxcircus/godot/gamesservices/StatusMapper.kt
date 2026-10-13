package com.syntaxcircus.godot.gamesservices

import java.io.IOException

/**
 * Maps Play Games Services failures to the four status strings of the GDScript games-service contract. Pure and free of Android
 * types so it is unit-tested on the JVM; the plugin passes in the SDK's own status-code categories (checked at compile time
 * against the libraries) instead of this class hard-coding numbers.
 *
 * The contract the game builds its retry queue on: offline and other self-healing problems are UNAVAILABLE (kept, no attempt
 * counted); a missing or declined sign-in is SIGNED_OUT; FAILED is only for errors that will not fix themselves.
 */
class StatusMapper(
    private val signedOutCodes: Set<Int>,
    private val networkCodes: Set<Int>,
) {
    fun fromStatusCode(code: Int): String = when {
        code == SUCCESS -> COMPLETED
        code in signedOutCodes -> SIGNED_OUT
        code in networkCodes -> UNAVAILABLE
        else -> FAILED
    }

    /** [statusCode] is the `ApiException` status code when the throwable carries one. */
    fun fromThrowable(error: Throwable, statusCode: Int?): String = when {
        statusCode != null -> fromStatusCode(statusCode)
        error is IOException -> UNAVAILABLE
        else -> FAILED
    }

    companion object {
        const val COMPLETED = "completed"
        const val SIGNED_OUT = "signed_out"
        const val UNAVAILABLE = "unavailable"
        const val FAILED = "failed"
        private const val SUCCESS = 0
    }
}
