import javax.swing.BorderFactory;
import javax.swing.JFrame;
import javax.swing.JScrollPane;
import javax.swing.JTextArea;
import javax.swing.SwingUtilities;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

public final class DesktopHost {
    private static final int GUEST_TIMEOUT_SECONDS = 10;

    private DesktopHost() { }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: DesktopHost <stitched-app.ores>");
        }

        AppManifest app = loadManifest(Path.of(args[0]));

        SwingUtilities.invokeAndWait(() -> {
            JTextArea text = new JTextArea(app.body());
            text.setEditable(false);
            text.setLineWrap(true);
            text.setWrapStyleWord(true);
            text.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));

            JFrame frame = new JFrame(app.title());
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setContentPane(new JScrollPane(text));
            frame.setSize(app.width(), app.height());
            frame.setLocationByPlatform(true);
            frame.setVisible(true);
        });
    }

    private static AppManifest loadManifest(Path source) throws Exception {
        String compiler = System.getenv().getOrDefault("ORESLANG_COMPILER", "oreslang-compiler");
        List<String> command = new ArrayList<>();
        command.add(compiler);
        command.add("--platform=" + oreslangPlatform());
        command.add(source.toString());

        Process process = new ProcessBuilder(command).start();
        if (!process.waitFor(GUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            throw new IllegalStateException("Oreslang guest exceeded the demo timeout");
        }

        String stdout = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        String stderr = new String(process.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
        if (process.exitValue() != 0) {
            throw new IllegalStateException("Oreslang guest failed: " + stderr);
        }

        List<String> lines = stdout.lines().toList();
        if (lines.size() != 4) {
            throw new IllegalStateException("expected four Oreslang manifest lines, got " + lines.size());
        }

        return new AppManifest(
                lines.get(0),
                Integer.parseInt(lines.get(1)),
                Integer.parseInt(lines.get(2)),
                lines.get(3)
        );
    }

    private static String oreslangPlatform() {
        String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (os.contains("mac")) return "macos";
        if (os.contains("win")) return "windows";
        return "linux";
    }

    private record AppManifest(String title, int width, int height, String body) { }
}
