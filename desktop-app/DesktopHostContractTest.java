import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.FutureTask;

/** Host-process integration checks. Does not invoke or certify an Oreslang compiler. */
public final class DesktopHostContractTest {
    private DesktopHostContractTest() { }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Process startHost(Path source, Path compiler) throws Exception {
        String executable = Path.of(System.getProperty("java.home"), "bin", "java")
                .toString();
        ProcessBuilder pb = new ProcessBuilder(
                executable, "-cp", "desktop-app", "DesktopHost",
                "--manifest-only", source.toString());
        pb.environment().put("ORESLANG_COMPILER", compiler.toString());
        pb.redirectErrorStream(true);
        return pb.start();
    }

    public static void main(String[] args) throws Exception {
        if (System.getProperty("os.name").toLowerCase(Locale.ROOT).contains("win")) {
            System.out.println("DESKTOP_HOST_DEADLINE_SKIPPED_WINDOWS");
            return;
        }
        Path dir = Files.createTempDirectory("ores-desktop-host-contract-");
        Path source = dir.resolve("demo.ores");
        Path compiler = dir.resolve("fake-compiler.sh");
        try {
            Files.writeString(source, "not a real Oreslang program\n");
            Files.writeString(compiler, "#!/bin/sh\n"
                    + "printf 'Demo title\\n640\\n360\\nDemo body\\n'\n");
            require(compiler.toFile().setExecutable(true), "compiler chmod");
            Process ok = startHost(source, compiler);
            try {
                require(ok.waitFor(5, TimeUnit.SECONDS), "clean fake compiler hung");
                require(ok.exitValue() == 0, "clean manifest rejected");
                String out = new String(ok.getInputStream().readAllBytes(),
                        StandardCharsets.UTF_8);
                require(out.equals("Demo title\n640\n360\nDemo body\n"),
                        "manifest mismatch");
            } finally {
                if (ok.isAlive()) ok.destroyForcibly();
            }

            // A real guest that never exits must honor the same wall deadline.
            Files.writeString(compiler, "#!/bin/sh\n"
                    + "sleep 16\n");
            long started = System.nanoTime();
            Process stuck = startHost(source, compiler);
            try {
                boolean exited = stuck.waitFor(13, TimeUnit.SECONDS);
                long elapsedMs = TimeUnit.NANOSECONDS.toMillis(
                        System.nanoTime() - started);
                require(exited, "hung compiler held host indefinitely");
                require(stuck.exitValue() != 0, "hung compiler accepted as valid");
                require(elapsedMs < 13_000L, "process deadline exceeded");
            } finally {
                if (stuck.isAlive()) stuck.destroyForcibly();
            }

            // An inherited/open pipe can keep a capture Future incomplete
            // even AFTER process.waitFor returns. Exercise the actual
            // capture-deadline method with a never-completing Future.
            Method capture = DesktopHost.class.getDeclaredMethod(
                    "getCaptured", java.util.concurrent.Future.class,
                    String.class, long.class);
            capture.setAccessible(true);
            FutureTask<String> blocked = new FutureTask<>(() -> "unreachable");
            boolean timedOut = false;
            try {
                capture.invoke(null, blocked, "stdout",
                        System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(50));
            } catch (InvocationTargetException error) {
                timedOut = error.getCause() instanceof IllegalStateException
                        && error.getCause().getMessage().contains("deadline");
            }
            require(timedOut, "never-completing capture Future was accepted");
            System.out.println("DESKTOP_HOST_GUEST_DEADLINE_PASS (fake compiler only)");
        } finally {
            Files.deleteIfExists(compiler);
            Files.deleteIfExists(source);
            Files.deleteIfExists(dir);
        }
    }
}
