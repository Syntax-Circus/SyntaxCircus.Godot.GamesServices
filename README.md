# SyntaxCircus.Godot.GamesServices

Leaderboards and achievements for Godot 4 mobile games behind one small GDScript interface, with a native Android
(Google Play Games Services v2) plugin and an adapter for Apple Game Center.

> **No support guaranteed.** Published as-is and maintained on a best-effort basis. Issues and PRs are welcome, but there's no
> SLA: fork it or vendor what you need if that's not enough.

## What you get

| Piece | Where | What it is |
|---|---|---|
| The contract | `addons/syntaxcircus_games/games_service.gd` | `RefCounted` interface: `sign_in`, `submit_score`, `show_board`, `unlock`, `report_progress`, `show_achievements`, each answering exactly once with `completed`, `signed_out`, `unavailable` or `failed` |
| Null and fake | `null_games_service.gd`, `fake_games_service.gd` | Desktop/headless and test implementations |
| Android adapter | `android_games_service.gd` | Drives the `SyntaxCircusGames` engine singleton |
| Apple adapter | `apple_games_service.gd` | Drives the [GameCenterKit](https://github.com/keremvatandas/godot-ios-gamecenter) singleton (vendored by the game) |
| Android plugin | `android/` (Kotlin) and `addons/syntaxcircus_games/bin/*.aar` | One class, nothing runs at load; `initialize()` is called by the adapter on first sign-in |
| Export plugin | `addons/syntaxcircus_games/export_plugin.gd` | Adds the AAR, the games-v2 dependency and the `APP_ID` meta-data |

The result codes are the point: **offline is `unavailable`** (keep the item and try again, no attempt counted), a declined
sign-in is `signed_out`, and `failed` is reserved for errors that will not fix themselves (unknown board id, developer
error). A game queue built on this can retry safely.

## Using it in a game

1. Copy `addons/syntaxcircus_games/` into your project (or take the release zip and its `manifest.json` and verify the
   hashes), and enable the plugin in Project Settings.
2. Set the export option `syntaxcircus_games/play_games_app_id` on the Android preset to your Play Games Services project id.
   Leave it empty and the plugin adds nothing, so a build without a project id simply has no games service.
3. Pick an adapter at start-up:

```gdscript
const Android = preload("res://addons/syntaxcircus_games/android_games_service.gd")
const Apple = preload("res://addons/syntaxcircus_games/apple_games_service.gd")
const Null = preload("res://addons/syntaxcircus_games/null_games_service.gd")

func make_games_service() -> RefCounted:
	if Android.available(): return Android.new()
	if Apple.available(): return Apple.new()
	return Null.new()
```

4. Call `sign_in()` only after your own consent or age gate. Nothing in the plugin initialises the Play Games SDK or
   authenticates a player before that call.

## Android plugin singleton

`SyntaxCircusGames` methods: `initialize()`, `sign_in(request)`, `is_authenticated()`, `submit_score(board, score, request)`,
`show_leaderboard(board, time_span, request)` (`-1` default, `0` daily, `1` weekly, `2` all time), `unlock(id, request)`,
`set_steps(id, steps, request)`, `show_achievements(request)`. Signals: `sign_in_result`, `score_result`,
`achievement_result`, `board_closed`, each `(request: int, status: String, message: String)`.

## Building

```powershell
./publish.ps1 -DryRun        # builds the AAR, runs tests, writes dist/<version>/ (zip + manifest.json)
```

Needs JDK 17 and the Android SDK (`ANDROID_HOME`), Godot 4.7.2 for the GDScript tests.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
