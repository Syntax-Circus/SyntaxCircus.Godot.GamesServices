# Changelog

## 0.1.0 (unreleased)

- The GDScript contract (`games_service.gd`) with null and fake services.
- `android_games_service.gd` and the `SyntaxCircusGames` Kotlin plugin (Play Games Services v2: sign in, leaderboards with a
  time span, achievements by steps), answering with `completed`, `signed_out`, `unavailable` or `failed`.
- `apple_games_service.gd` driving the GameCenterKit singleton, with conservative error classification.
- `export_plugin.gd`: adds the AAR, the games-v2 dependency and the `APP_ID` meta-data only when the preset names a project id.
- `publish.ps1`: Gradle build, Kotlin and GDScript tests, `dist/<version>/` zip and `manifest.json`.
