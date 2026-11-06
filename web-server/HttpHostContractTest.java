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
