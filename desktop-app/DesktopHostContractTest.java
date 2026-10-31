import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

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

            // Compiler exits immediately, but its descendant holds the output
            // pipe open longer than the host's 10-second TOTAL deadline.
            Files.writeString(compiler, "#!/bin/sh\n"
                    + "sleep 16 &\n"
                    + "printf 'Demo title\\n640\\n360\\nDemo body\\n'\n");
            long started = System.nanoTime();
            Process stuck = startHost(source, compiler);
            try {
                boolean exited = stuck.waitFor(13, TimeUnit.SECONDS);
                long elapsedMs = TimeUnit.NANOSECONDS.toMillis(
                        System.nanoTime() - started);
                require(exited, "inherited compiler pipe held host indefinitely");
                require(stuck.exitValue() != 0, "incomplete pipe accepted as valid");
                require(elapsedMs < 13_000L, "capture deadline exceeded");
            } finally {
                if (stuck.isAlive()) stuck.destroyForcibly();
            }
            System.out.println("DESKTOP_HOST_GUEST_DEADLINE_PASS (fake compiler only)");
        } finally {
            Files.deleteIfExists(compiler);
            Files.deleteIfExists(source);
            Files.deleteIfExists(dir);
        }
    }
}
