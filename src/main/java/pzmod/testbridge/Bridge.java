package pzmod.testbridge;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import java.util.Locale;

/**
 * The command file: {@code <Zomboid>/testbridge/command.txt}, polled every 250 ms from the Lua tick (game thread, also on
 * the main menu), executed line by line, then deleted. Each line's result goes to console.txt as
 * {@code [TestBridge] command: <line> -> <result>} and, in full, to {@code testbridge/result.txt} (overwritten per line,
 * so a test reads the last line's result).
 * <pre>
 *   ping                 -> "pong" and the bridge version (is the game listening?)
 *   lua &lt;code&gt;           -> runs one line of Lua the way the game's debug console does
 *   luafile &lt;path&gt;       -> runs a whole file (absolute, or relative to testbridge/)
 *   cam [dx dy]          -> reads or sets player 0's camera offset from the character, in squares (0 0 = centred)
 *   zoom [z]             -> reads or sets player 0's zoom (bigger = farther)
 *   time [hour]          -> reads or sets the time of day (changes the save: test saves only)
 * </pre>
 */
final class Bridge {
    static final String VERSION = "1.0.0";
    private static final String TAG = "[TestBridge] ";
    private static long nextPoll;

    private Bridge() {}

    static void log(String msg) {
        System.out.println(TAG + msg);
    }

    static File dir() {
        String base;
        try {
            base = zombie.ZomboidFileSystem.instance.getCacheDir();
        } catch (Throwable t) {
            base = System.getProperty("user.home") + File.separator + "Zomboid";
        }
        File d = new File(base, "testbridge");
        d.mkdirs();
        return d;
    }

    /** Game thread, every frame (Lua OnPostUIDraw). */
    static void tick() {
        long now = System.nanoTime();
        if (now < nextPoll) return;
        nextPoll = now + 250_000_000L;
        File f = new File(dir(), "command.txt");
        if (!f.isFile()) return;
        List<String> lines;
        try {
            lines = Files.readAllLines(f.toPath(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return; // still being written: next poll
        }
        if (!f.delete()) log("could not delete " + f);
        for (String line : lines) {
            String l = line.trim();
            if (l.isEmpty() || l.startsWith("#")) continue;
            String out = run(l);
            write(out);
            log("command: " + l + " -> " + (out.length() > 2000 ? out.substring(0, 2000) + " ... (full: result.txt)" : out));
        }
    }

    static String run(String line) {
        String[] p = line.split("\\s+");
        String rest = line.length() > p[0].length() ? line.substring(p[0].length()).trim() : "";
        try {
            return switch (p[0].toLowerCase(Locale.ROOT)) {
                case "ping" -> "pong TestBridge " + VERSION;
                case "lua" -> lua(rest, "testbridge");
                case "luafile" -> luaFile(rest);
                case "cam" -> cam(p);
                case "zoom" -> zoom(p);
                case "time" -> time(p);
                default -> "error: unknown command (ping, lua, luafile, cam, zoom, time)";
            };
        } catch (Throwable t) {
            return "error: " + t;
        }
    }

    private static void write(String out) {
        try {
            Files.writeString(new File(dir(), "result.txt").toPath(), out + "\n", StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            // the console line still has it
        }
    }

    /** Lua source in the game's Lua state, as UIDebugConsole does; "ok: results" or "error: message | stack". */
    static String lua(String src, String chunk) {
        try {
            se.krka.kahlua.vm.LuaClosure closure =
                    se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(src, chunk, zombie.Lua.LuaManager.env);
            se.krka.kahlua.integration.LuaReturn r =
                    zombie.Lua.LuaManager.caller.protectedCall(zombie.Lua.LuaManager.thread, closure);
            if (!r.isSuccess()) {
                return "error: " + r.getErrorString() + (r.getLuaStackTrace() != null ? " | " + r.getLuaStackTrace() : "");
            }
            StringBuilder b = new StringBuilder("ok:");
            for (Object o : r) b.append(' ').append(o);
            return b.toString();
        } catch (Exception e) {
            return "error: " + e;
        }
    }

    private static String luaFile(String path) {
        File f = new File(path);
        if (!f.isAbsolute()) f = new File(dir(), path);
        try {
            return lua(Files.readString(f.toPath(), StandardCharsets.UTF_8), f.getName());
        } catch (Exception e) {
            return "error: cannot read " + f + ": " + e;
        }
    }

    /** Vanilla's debug states pan the camera with the same field. */
    private static String cam(String[] p) {
        zombie.iso.PlayerCamera c = zombie.iso.IsoCamera.cameras[0];
        if (p.length > 2) {
            c.deferedX = (float) parse(p[1]);
            c.deferedY = (float) parse(p[2]);
        }
        return "ok: cam dx=" + c.deferedX + " dy=" + c.deferedY;
    }

    private static String zoom(String[] p) {
        zombie.core.textures.MultiTextureFBO2 b = zombie.core.Core.getInstance().offscreenBuffer;
        if (b == null) return "error: no world view (main menu?)";
        if (p.length > 1 && parse(p[1]) > 0) b.setZoomAndTargetZoom(0, (float) parse(p[1]));
        return "ok: zoom=" + b.getZoom(0) + " display=" + b.getDisplayZoom(0);
    }

    private static String time(String[] p) {
        zombie.GameTime gt = zombie.GameTime.getInstance();
        if (gt == null) return "error: no game time";
        if (p.length > 1) {
            double h = parse(p[1]);
            if (h >= 0 && h < 24) gt.setTimeOfDay((float) h);
        }
        return "ok: timeOfDay=" + gt.getTimeOfDay();
    }

    private static double parse(String s) {
        try {
            return Double.parseDouble(s);
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
