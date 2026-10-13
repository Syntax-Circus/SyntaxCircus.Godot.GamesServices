# Workspace preference

Use feature branches in the existing checkout. Do not create Git worktrees; the repository owner explicitly dislikes them.

# Notes for agents

- The GDScript contract in `addons/syntaxcircus_games/` is consumed by copying (vendoring) into game repos with a hash
  manifest. Keep it free of any game-specific path, save format or id scheme.
- Result codes are a published contract: offline and other self-healing errors are `unavailable`, never `failed`.
- Nothing may initialise the Play Games SDK or authenticate a player at plugin load. `initialize()` and `sign_in()` are called
  by the game after its consent gate.
- Tests: `godot --headless --path . --script res://tests/<name>.gd` for GDScript, `./android/gradlew -p android test` for Kotlin.
