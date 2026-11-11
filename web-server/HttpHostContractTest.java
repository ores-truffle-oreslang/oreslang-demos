public final class HttpHostContractTest {
    private HttpHostContractTest() { }

    public static void main(String[] args) throws Exception {
        accept("/");
        accept("/health");
        accept("/assets/app-v1");

        reject("", null);
        reject("health", null);
        reject("/health", "debug=1");
        reject("/%68ealth", null);
        reject("/a/../health", null);
        reject("/a/./health", null);
        reject("//health", null);
        reject("/a//b", null);
        reject("/a\\b", null);
        reject("/snowman-☃", null);

        // Path caps are inclusive. Never truncate or normalize a hostile URL
        // into a different route before admitting the exact raw target.
        accept("/" + "a".repeat(2047));
        reject("/" + "a".repeat(2048), null);

        // Query presence is forbidden even for a zero-length query.
        reject("/health", "");
        reject(null, null);
        for (String malformed : new String[] {
                "/health?debug=1",
                "/health#fragment",
                "/a%2fb",
                "/a%2Eb",
                "/bad\rheader",
                "/bad\nheader",
                "/bad\tpath",
                "/bad" + ((char) 0) + "path"
        }) {
            reject(malformed, null);
        }

        // The raw request target must reject every ASCII control/space
        // byte, even when it appears after an otherwise valid route prefix.
        for (int ch = 0; ch <= 0x20; ++ch) {
            reject("/health" + (char) ch, null);
        }
        reject("/health" + (char) 0x7f, null);
        // A literal unpaired surrogate and valid non-ASCII scalar alike
        // are outside the deliberately ASCII-only host route contract.
        reject("/health" + (char) 0xd800, null);
        reject("/health" + (char) 0xdc00, null);
        reject("/health" + "\u00e9", null);

        // Endpoints of admitted printable ASCII remain valid; the gate
        // must not accidentally overblock punctuation or near-dot names.
        accept("/!");
        accept("/~");
        accept("/..hidden");
        accept("/a.b");
        accept("/a:b@c");

        testBoundedCaptureDeadline();
        testHungCompilerAndDescendantCleanup();
        System.out.println("HTTP host target and guest-deadline contract tests passed");
    }

    private static void accept(String path) {
        if (!HttpHost.canonicalRequestTarget(path, null)) {
            throw new AssertionError("canonical target rejected: " + path);
        }
    }

    private static void reject(String path, String query) {
        if (HttpHost.canonicalRequestTarget(path, query)) {
            throw new AssertionError("noncanonical target accepted: " + path);
        }
    }

    // Host-only regression: no compiler is invoked, and a permanently
    // incomplete stdout/stderr Future may never hang a demo host.
    private static void testBoundedCaptureDeadline() throws Exception {
        java.lang.reflect.Method method = HttpHost.class.getDeclaredMethod(
                "getCaptured", java.util.concurrent.Future.class,
                String.class, long.class);
        method.setAccessible(true);
        java.util.concurrent.FutureTask<String> stalled =
                new java.util.concurrent.FutureTask<>(() -> "never completed");
        boolean rejected = false;
        try {
            method.invoke(null, stalled, "stdout",
                    System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(50));
        } catch (java.lang.reflect.InvocationTargetException error) {
            rejected = error.getCause() instanceof IllegalStateException
                    && error.getCause().getMessage().contains("deadline");
        }
        if (!rejected) throw new AssertionError("stalled output capture was not bounded");
    }

    // Host-only process regression: a fake compiler spawns a process retaining
    // inherited pipes. HttpHost must exit before that child finishes sleeping.
    private static void testHungCompilerAndDescendantCleanup() throws Exception {
        if (System.getProperty("os.name", "").toLowerCase(java.util.Locale.ROOT)
                .contains("win")) {
            System.out.println("HTTP_HOST_PROCESS_TEST_SKIPPED_WINDOWS");
            return;
        }
        java.nio.file.Path dir =
                java.nio.file.Files.createTempDirectory("ores-http-host-contract-");
        java.nio.file.Path source = dir.resolve("fake.ores");
        java.nio.file.Path compiler = dir.resolve("fake-compiler.sh");
        java.nio.file.Path pidFile = dir.resolve("fake-compiler.sh.child-pid");
        Process host = null;
        try {
            java.nio.file.Files.writeString(source, "not a real AttoLang program\n");
            java.nio.file.Files.writeString(compiler, "#!/bin/sh\n"
                    + "sleep 30 &\n"
                    + "printf '%s\\n' \"$!\" > \"$0.child-pid\"\n"
                    + "wait\n");
            if (!compiler.toFile().setExecutable(true)) {
                throw new AssertionError("fake compiler chmod failed");
            }

            String java = java.nio.file.Path.of(System.getProperty("java.home"),
                    "bin", "java").toString();
            ProcessBuilder pb = new ProcessBuilder(java, "-cp", "web-server",
                    "HttpHost", source.toString());
            pb.environment().put("ORESLANG_COMPILER", compiler.toString());
            pb.redirectErrorStream(true);
            long started = System.nanoTime();
            host = pb.start();
            if (!host.waitFor(13, java.util.concurrent.TimeUnit.SECONDS)) {
                throw new AssertionError("HTTP host hung on fake compiler or inherited pipe");
            }
            long elapsedMs = java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(
                    System.nanoTime() - started);
            if (host.exitValue() == 0 || elapsedMs >= 13_000) {
                throw new AssertionError("HTTP host failed its guest deadline");
            }
            if (!java.nio.file.Files.isRegularFile(pidFile)) {
                throw new AssertionError("fake compiler did not spawn expected child");
            }
            long pid = Long.parseLong(java.nio.file.Files.readString(pidFile).trim());
            long until = System.nanoTime()
                    + java.util.concurrent.TimeUnit.SECONDS.toNanos(2);
            while (ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false)
                    && System.nanoTime() < until) {
                Thread.sleep(25);
            }
            if (ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false)) {
                throw new AssertionError("fake compiler descendant survived cleanup");
            }
        } finally {
            if (host != null && host.isAlive()) host.destroyForcibly();
            if (java.nio.file.Files.isRegularFile(pidFile)) {
                try {
                    long pid = Long.parseLong(java.nio.file.Files.readString(pidFile).trim());
                    ProcessHandle.of(pid).ifPresent(ProcessHandle::destroyForcibly);
                } catch (NumberFormatException ignored) {
                    // The PID file is owned by a fake compiler, not trusted input.
                }
            }
            java.nio.file.Files.deleteIfExists(pidFile);
            java.nio.file.Files.deleteIfExists(compiler);
            java.nio.file.Files.deleteIfExists(source);
            java.nio.file.Files.deleteIfExists(dir);
        }
    }

}
