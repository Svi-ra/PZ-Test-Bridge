package pzmod.testbridge;

import se.krka.kahlua.integration.annotations.LuaMethod;

/**
 * Lua globals. ZombieBuddy discovers them because the class has static {@code @LuaMethod(global = true)} methods in our
 * package.
 * <pre>
 *   TestBridge_tick()         -> polls the command file; called every frame by our Lua (OnPostUIDraw)
 *   TestBridge_command(line)  -> runs one bridge command from Lua (e.g. "cam 2 0") and returns its result
 * </pre>
 */
public final class LuaApi {
    public LuaApi() {}

    @LuaMethod(name = "TestBridge_tick", global = true)
    public static void tick() {
        try {
            Bridge.tick();
        } catch (Throwable t) {
            Bridge.log("tick failed: " + t);
        }
    }

    @LuaMethod(name = "TestBridge_command", global = true)
    public static String command(String line) {
        return Bridge.run(line == null ? "" : line.trim());
    }
}
