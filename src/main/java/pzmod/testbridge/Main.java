package pzmod.testbridge;

/** ZombieBuddy entry point ({@code <javaPkgName>.Main.main}), run once when ZombieBuddy loads the jar. */
public final class Main {
    private Main() {}

    public static void main(String[] args) {
        Bridge.log("v" + Bridge.VERSION + " loaded (java " + System.getProperty("java.version")
                + "). Development tool: commands from " + Bridge.dir() + "/command.txt; Lua library TB.");
    }
}
