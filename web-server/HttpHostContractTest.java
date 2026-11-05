public final class HttpHostContractTest {
    private HttpHostContractTest() { }

    public static void main(String[] args) {
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
                "/bad\u0000path"
        }) {
            reject(malformed, null);
        }

        System.out.println("HTTP host target contract tests passed");
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
}
