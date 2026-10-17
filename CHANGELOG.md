# Changelog

## Unreleased

- Release workflow: avoid the retired Android SDK `tools` package when building tagged releases.

## 0.1.2 (2026-10-14)

- Android: the Play Games SDK no longer starts on its own. The plugin manifest removes `PlayGamesInitProvider` and sets
  `SUPPRESS_GAME_PROFILE_CREATION`; the SDK is initialized on the first `sign_in()`, so the game controls when it starts
  (for example after its own consent gate). A manifest-merge test covers this.
- Pushing a stable `vX.Y.Z` tag now builds, tests and publishes a GitHub release with the addon zip and `manifest.json`
  (the manifest records the source commit and SHA-256 hashes).

## 0.1.1 (2026-10-14)

- `load_player_rank(board_id, request)` and the `rank_finished` signal: the local player's global all-time rank on a
  leaderboard (zero means no ranked score), on the contract, the null and fake services, and the Android and Apple adapters.
- Android request ids are now unique across adapter instances.

## 0.1.0 (2026-10-13)

- The GDScript contract (`games_service.gd`) with null and fake services.
- `android_games_service.gd` and the `SyntaxCircusGames` Kotlin plugin (Play Games Services v2: sign in, leaderboards with a
  time span, achievements by steps), answering with `completed`, `signed_out`, `unavailable` or `failed`.
- `apple_games_service.gd` driving the GameCenterKit singleton, with conservative error classification.
- `export_plugin.gd`: adds the AAR, the games-v2 dependency and the `APP_ID` meta-data only when the preset names a project id.
- `publish.ps1`: Gradle build, Kotlin and GDScript tests, `dist/<version>/` zip and `manifest.json`.
