package com.syntaxcircus.godot.gamesservices

import android.content.Intent
import android.util.Log
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.games.GamesClientStatusCodes
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.tasks.Task
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Google Play Games Services v2 for Godot 4: sign in, leaderboards and achievements behind a handful of methods that answer with
 * the status strings of the GDScript games-service contract (see [StatusMapper]).
 *
 * Nothing happens at load. The game calls [initialize] and [sign_in] after its own consent gate; every other method needs a
 * signed-in player and answers SIGNED_OUT through its signal otherwise. Every call takes a request id and answers exactly once
 * with that id, so the GDScript adapter can ignore late or repeated answers.
 */
class GamesServicesPlugin(godot: Godot) : GodotPlugin(godot) {
    private val mapper = StatusMapper(
        signedOutCodes = setOf(
            CommonStatusCodes.SIGN_IN_REQUIRED,
            CommonStatusCodes.RESOLUTION_REQUIRED,
            CommonStatusCodes.CANCELED,
        ),
        networkCodes = setOf(
            CommonStatusCodes.NETWORK_ERROR,
            CommonStatusCodes.TIMEOUT,
            CommonStatusCodes.API_NOT_CONNECTED,
            CommonStatusCodes.INTERNAL_ERROR,
            CommonStatusCodes.INTERRUPTED,
            CommonStatusCodes.RECONNECTION_TIMED_OUT,
            CommonStatusCodes.RECONNECTION_TIMED_OUT_DURING_UPDATE,
            CommonStatusCodes.CONNECTION_SUSPENDED_DURING_CALL,
            CommonStatusCodes.REMOTE_EXCEPTION,
            GamesClientStatusCodes.NETWORK_ERROR_NO_DATA,
            GamesClientStatusCodes.NETWORK_ERROR_OPERATION_FAILED,
            GamesClientStatusCodes.OPERATION_IN_FLIGHT,
        ),
    )

    private val signInResult = SignalInfo("sign_in_result", Int::class.javaObjectType, String::class.java, String::class.java)
    private val scoreResult = SignalInfo("score_result", Int::class.javaObjectType, String::class.java, String::class.java)
    private val achievementResult = SignalInfo("achievement_result", Int::class.javaObjectType, String::class.java, String::class.java)
    private val boardClosed = SignalInfo("board_closed", Int::class.javaObjectType)

    @Volatile private var authenticated = false
    @Volatile private var pendingBoardRequest = NO_REQUEST

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(signInResult, scoreResult, achievementResult, boardClosed)

    /** Starts the Play Games SDK. The game calls this from its first sign in, never at app start. */
    @UsedByGodot
    fun initialize() {
        val host = activity
        if (host == null) {
            Log.w(TAG, "initialize() before an activity exists")
            return
        }
        PlayGamesSdk.initialize(host)
    }

    @UsedByGodot
    fun is_authenticated(): Boolean = authenticated

    @UsedByGodot
    fun sign_in(request: Int) {
        val host = activity ?: return answer(signInResult, request, StatusMapper.UNAVAILABLE, "no activity")
        val client = PlayGames.getGamesSignInClient(host)
        client.isAuthenticated.addOnCompleteListener { check ->
            if (check.isSuccessful && check.result.isAuthenticated) {
                authenticated = true
                answer(signInResult, request, StatusMapper.COMPLETED, "")
                return@addOnCompleteListener
            }
            // Not signed in (or the check failed): ask, which shows Google's own UI only when it has to.
            client.signIn().addOnCompleteListener { attempt ->
                if (attempt.isSuccessful) {
                    authenticated = attempt.result.isAuthenticated
                    answer(signInResult, request, if (authenticated) StatusMapper.COMPLETED else StatusMapper.SIGNED_OUT, "")
                } else {
                    authenticated = false
                    answer(signInResult, request, statusOf(attempt), messageOf(attempt))
                }
            }
        }
    }

    /** `score` is an int on this side: every encoding in the game fits a signed 32-bit integer. */
    @UsedByGodot
    fun submit_score(board: String, score: Int, request: Int) {
        val host = activity ?: return answer(scoreResult, request, StatusMapper.UNAVAILABLE, "no activity")
        PlayGames.getLeaderboardsClient(host).submitScoreImmediate(board, score.toLong()).addOnCompleteListener { task ->
            if (task.isSuccessful) answer(scoreResult, request, StatusMapper.COMPLETED, "")
            else answer(scoreResult, request, statusOf(task), messageOf(task))
        }
    }

    /** `time_span`: -1 the SDK default, 0 daily, 1 weekly, 2 all time (the SDK's LeaderboardVariant spans). */
    @UsedByGodot
    fun show_leaderboard(board: String, time_span: Int, request: Int) {
        val host = activity ?: return closeBoard(request)
        val client = PlayGames.getLeaderboardsClient(host)
        val intent = if (time_span < 0) client.getLeaderboardIntent(board) else client.getLeaderboardIntent(board, time_span)
        showIntent(intent, request)
    }

    @UsedByGodot
    fun unlock(id: String, request: Int) {
        val host = activity ?: return answer(achievementResult, request, StatusMapper.UNAVAILABLE, "no activity")
        PlayGames.getAchievementsClient(host).unlockImmediate(id).addOnCompleteListener { task ->
            if (task.isSuccessful) answer(achievementResult, request, StatusMapper.COMPLETED, "")
            else answer(achievementResult, request, statusOf(task), messageOf(task))
        }
    }

    /** Sets the step count to at least [steps]: repeating a call or sending an older value changes nothing. */
    @UsedByGodot
    fun set_steps(id: String, steps: Int, request: Int) {
        val host = activity ?: return answer(achievementResult, request, StatusMapper.UNAVAILABLE, "no activity")
        PlayGames.getAchievementsClient(host).setStepsImmediate(id, steps).addOnCompleteListener { task ->
            if (task.isSuccessful) answer(achievementResult, request, StatusMapper.COMPLETED, "")
            else answer(achievementResult, request, statusOf(task), messageOf(task))
        }
    }

    @UsedByGodot
    fun show_achievements(request: Int) {
        val host = activity ?: return closeBoard(request)
        showIntent(PlayGames.getAchievementsClient(host).achievementsIntent, request)
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        if (requestCode != BOARD_REQUEST_CODE) return
        val request = pendingBoardRequest
        pendingBoardRequest = NO_REQUEST
        if (request != NO_REQUEST) answer(boardClosed, request)
    }

    private fun showIntent(task: Task<Intent>, request: Int) {
        task.addOnCompleteListener { result ->
            val host = activity
            if (!result.isSuccessful || host == null) {
                // A board that cannot open is a normal outcome for the game: it only needs the one answer.
                Log.w(TAG, "Board did not open: ${messageOf(result)}")
                closeBoard(request)
                return@addOnCompleteListener
            }
            pendingBoardRequest = request
            host.startActivityForResult(result.result, BOARD_REQUEST_CODE)
        }
    }

    private fun closeBoard(request: Int) = answer(boardClosed, request)

    private fun statusOf(task: Task<*>): String {
        val error = task.exception ?: return StatusMapper.FAILED
        val status = mapper.fromThrowable(error, (error as? ApiException)?.statusCode)
        if (status == StatusMapper.SIGNED_OUT) authenticated = false
        return status
    }

    /** The exception text can name the player's account, so only its type and status code are passed to the game and the log. */
    private fun messageOf(task: Task<*>): String {
        val error = task.exception ?: return ""
        val code = (error as? ApiException)?.statusCode
        return if (code != null) "${error.javaClass.simpleName}:$code" else error.javaClass.simpleName
    }

    private fun answer(signal: SignalInfo, request: Int, status: String, message: String) {
        runOnHostThread { emitSignal(signal, request, status, message) }
    }

    private fun answer(signal: SignalInfo, request: Int) {
        runOnHostThread { emitSignal(signal, request) }
    }

    private companion object {
        const val PLUGIN_NAME = "SyntaxCircusGames"
        const val TAG = "SyntaxCircusGames"
        const val BOARD_REQUEST_CODE = 0x5C61
        const val NO_REQUEST = -1
    }
}
