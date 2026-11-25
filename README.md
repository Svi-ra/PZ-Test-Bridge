# Test Bridge (Project Zomboid, Build 42)

A development-only mod that lets automated tests (and AI agents) drive a running game through a command file. It
replaces nothing in the game and does nothing until a command file appears. Not for play, not for the Workshop.

Requires ZombieBuddy (Java mods), Build 42.22+. Enable it next to the mod under test, in the save you test with.

**After enabling it for the first time, restart the game.** ZombieBuddy hands Java functions to Lua once, at start-up;
a jar enabled later from the main menu loads, but `TestBridge_tick` stays missing in Lua until the next start, so the
command file is never read (console.txt shows `[TestBridge] v... loaded` and no `command:` lines).

## How it works

- The mod's Lua calls `TestBridge_tick()` every frame (`OnPostUIDraw`: in game and on the main menu). Every 250 ms the
  Java side looks for `<Zomboid>/testbridge/command.txt`, runs its lines, and deletes it.
- Each result goes to `console.txt` as `[TestBridge] command: <line> -> <result>` and, in full, to
  `<Zomboid>/testbridge/result.txt` (the last line's result).

| Command | Does |
|---|---|
| `ping` | `pong TestBridge <version>`: is the game listening? |
| `lua <code>` | one line of Lua, run like the game's debug console (`LuaCompiler.loadstring` + `LuaManager.caller.protectedCall`); `ok: <results>` or `error: <message> \| <stack>` |
| `luafile <path>` | a whole file (absolute, or relative to `testbridge/`); also reloads a mod's Lua file into the running game |
| `cam [dx dy]` | player 0's camera offset from the character in squares (`cam 0 0` re-centres) |
| `zoom [z]` | player 0's zoom (bigger = farther) |
| `time [hour]` | time of day (changes the save) |

The Lua library `TB` (`media/lua/client/TestBridge/TestBridge.lua`), called with `lua return TB.<fn>(...)`:

| Area | Functions |
|---|---|
| Player | `TB.pos()`, `TB.tp(x, y [, z])`, `TB.walk(x, y [, z])` (pathfinding), `TB.stop()`, `TB.face(x, y)`, `TB.safe(on)` (god mode + invisible + ghost), `TB.speed(n)` (0 pauses) |
| Camera | `TB.cam(dx, dy)`, `TB.zoom(z)`, `TB.time(hour)`, `TB.screen(x, y [, z])` (window pixel of a world point) |
| UI | `TB.ui([filter])` lists visible elements as `id Type 'text' x,y wxh` (context menu options as `id/opt N 'name'`); `TB.click(id or text)` through the element's own handlers; `TB.text(target, s)`; `TB.close(target)`; `TB.shot(name)` saves the frame with UI to `<Zomboid>/Screenshots/<name>.png` |
| Menus | `TB.rmenu(x, y [, z])` opens a square's world context menu as a right-click does; `TB.option(text)` picks an option |
| State | `TB.state()` (`mainmenu` / `ingame [paused] [escmenu]`, screen size, mouse); `TB.continue()` loads the latest save |

A shell client and the full workflow (launching, waiting for the save, real input through computer use) are in the
Claude skill `pz-game-control` (`~/.claude/skills/pz-game-control`).

## Build

Copy `gradle.properties.example` to `gradle.properties` and set the paths. With the game closed:

    ./gradlew deployMod      # builds TestBridge.jar and copies the mod to <modsDir>/TestBridge

Never deploy while the game runs: ZombieBuddy has the old jar open and classes not loaded yet fail. After a jar change,
ZombieBuddy asks at start-up to approve the new jar.

## Safety

The command file runs arbitrary Lua with the game's permissions. Only the local user (and tools they run) can write to
the Zomboid user folder, but do not leave the mod enabled in saves you play, and never ship it.
