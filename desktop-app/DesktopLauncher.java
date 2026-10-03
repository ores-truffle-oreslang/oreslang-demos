import javax.swing.BorderFactory;
import javax.swing.JFrame;
import javax.swing.JScrollPane;
import javax.swing.JTextArea;
import javax.swing.SwingUtilities;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

public final class DesktopLauncher {
    private DesktopLauncher() { }

    public static void main(String[] args) throws Exception {
        String guestOutput = runOreslang();

        SwingUtilities.invokeAndWait(() -> {
            JTextArea text = new JTextArea(guestOutput);
            text.setEditable(false);
            text.setLineWrap(true);
            text.setWrapStyleWord(true);
            text.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));

            JFrame frame = new JFrame("Oreslang Desktop Demo");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setContentPane(new JScrollPane(text));
            frame.setSize(640, 360);
            frame.setLocationByPlatform(true);
            frame.setVisible(true);
        });
    }

    private static String runOreslang() throws Exception {
        String compiler = System.getenv().getOrDefault("ORESLANG_COMPILER", "oreslang-compiler");

        List<String> command = new ArrayList<>();
        command.add(compiler);
        command.add("--platform=" + oreslangPlatform());
        command.add("app.ores");

        Process process = new ProcessBuilder(command).start();
        if (!process.waitFor(10, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            throw new IllegalStateException("Oreslang guest exceeded the 10 second demo timeout");
        }

        String stdout = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        String stderr = new String(process.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);

        if (process.exitValue() != 0) {
            throw new IllegalStateException("Oreslang guest failed with exit code "
                    + process.exitValue() + ": " + stderr);
        }

        return stdout;
    }

    private static String oreslangPlatform() {
        String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (os.contains("mac")) return "macos";
        if (os.contains("win")) return "windows";
        return "linux";
    }
}
