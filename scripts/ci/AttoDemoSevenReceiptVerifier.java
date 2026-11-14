import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

/**
 * Source-free, JDK-only verifier for seven exact named AttoLang guest tests.
 * A green host check or an arbitrary Surefire XML file is not guest evidence.
 */
public final class AttoDemoSevenReceiptVerifier {
    private static final String SUITE = "dev.oreslang.AttoDemoMultifileSevenCaseGuestTest";
    private static final List<String> METHODS = List.of(
            "linkedExtensionlessFunctionImportEmits42",
            "linkedAliasedModulePublicClassEmits42",
            "distinctMutableOwnerLoansEmit42",
            "missingRelativeImportRejectedAtCompileTime",
            "ambiguousExportedFunctionRejectedAtCompileTime",
            "doubleMutableBorrowOfOneOwnerRejectedAtCompileTime",
            "importedModuleAliasCannotLeakUnaliasedName");

    private static void require(boolean ok, String why) {
        if (!ok) throw new IllegalStateException("RECEIPT_REJECT: " + why);
    }

    private static int count(Element node, String attribute) {
        String value = node.getAttribute(attribute);
        require(value.matches("[0-9]{1,5}"), "invalid JUnit attribute " + attribute);
        return Integer.parseInt(value);
    }

    private static Document parse(Path file) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        factory.setXIncludeAware(false);
        factory.setExpandEntityReferences(false);
        var builder = factory.newDocumentBuilder();
        builder.setErrorHandler(new org.xml.sax.helpers.DefaultHandler() {
            @Override public void fatalError(org.xml.sax.SAXParseException problem) throws org.xml.sax.SAXException {
                throw problem;
            }
        });
        builder.setEntityResolver((publicId, systemId) -> {
            throw new IllegalStateException("external entity prohibited");
        });
        return builder.parse(file.toFile());
    }

    static int verify(String head, Path directory) throws Exception {
        require(head != null && head.matches("[0-9a-f]{40}"), "invalid exact Git head");
        require(directory != null && Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                && !Files.isSymbolicLink(directory), "report directory missing or symlinked");
        Path file = directory.resolve("TEST-" + SUITE + ".xml");
        require(Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS)
                        && !Files.isSymbolicLink(file) && Files.size(file) > 0
                        && Files.size(file) <= 1_048_576,
                "missing, symlinked, empty or oversized JUnit file");
        Element root = parse(file).getDocumentElement();
        require(root != null && "testsuite".equals(root.getTagName()), "unexpected XML root");
        require(SUITE.equals(root.getAttribute("name")), "incorrect JUnit suite");
        require(count(root, "tests") == METHODS.size(), "wrong test count");
        for (String key : List.of("failures", "errors", "skipped")) {
            require(count(root, key) == 0, "nonzero " + key);
        }
        NodeList cases = root.getElementsByTagName("testcase");
        require(cases.getLength() == METHODS.size(), "incorrect testcase count");
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < cases.getLength(); i++) {
            Element c = (Element) cases.item(i);
            require(c.getParentNode() == root, "nested testcase");
            require(SUITE.equals(c.getAttribute("classname")), "wrong testcase class");
            String name = c.getAttribute("name");
            require(METHODS.contains(name) && seen.add(name), "foreign/duplicate testcase");
            for (String bad : List.of("error", "failure", "skipped")) {
                require(c.getElementsByTagName(bad).getLength() == 0, "failed/skipped testcase");
            }
        }
        require(seen.containsAll(METHODS), "missing required methods");
        return seen.size();
    }

    private static String example() {
        StringBuilder s = new StringBuilder("<testsuite name=\"").append(SUITE)
                .append("\" tests=\"7\" errors=\"0\" failures=\"0\" skipped=\"0\">");
        for (String name : METHODS) {
            s.append("<testcase classname=\"").append(SUITE).append("\" name=\"")
                    .append(name).append("\"/>");
        }
        return s.append("</testsuite>").toString();
    }

    private static int deny(String label, String head, Path dir) throws Exception {
        try { verify(head, dir); }
        catch (Exception expected) { return 1; }
        throw new IllegalStateException("selftest improperly accepted " + label);
    }

    private static void selfTest() throws Exception {
        Path dir = Files.createTempDirectory("atto-demo-junit-");
        Path file = dir.resolve("TEST-" + SUITE + ".xml");
        String head = "0123456789abcdef0123456789abcdef01234567";
        String valid = example();
        int rejects = 0;
        try {
            Files.writeString(file, valid);
            require(verify(head, dir) == 7, "valid fixture rejected");
            rejects += deny("bad-head", "invalid", dir);
            Files.delete(file);
            rejects += deny("missing-file", head, dir);
            Files.writeString(file, "");
            rejects += deny("empty-file", head, dir);
            Files.writeString(file, "<testsuite");
            rejects += deny("malformed-XML", head, dir);
            Files.writeString(file, valid.replace("tests=\"7\"", "tests=\"0\""));
            rejects += deny("zero-tests", head, dir);
            Files.writeString(file, valid.replace("skipped=\"0\"", "skipped=\"1\""));
            rejects += deny("skipped-suite", head, dir);
            Files.writeString(file, valid.replace("failures=\"0\"", "failures=\"1\""));
            rejects += deny("failed-suite", head, dir);
            Files.writeString(file, valid.replace("errors=\"0\"", "errors=\"1\""));
            rejects += deny("errored-suite", head, dir);
            Files.writeString(file, valid.replace("name=\"" + SUITE, "name=\"foreign.ForgedSuite"));
            rejects += deny("wrong-suite", head, dir);
            Files.writeString(file, valid.replace("classname=\"" + SUITE, "classname=\"forged.OtherSuite"));
            rejects += deny("wrong-class", head, dir);
            Files.writeString(file, valid.replace("name=\"" + METHODS.get(1), "name=\"" + METHODS.get(0)));
            rejects += deny("duplicate-test", head, dir);
            Files.writeString(file, valid.replace("name=\"" + METHODS.get(1), "name=\"newUnexpectedTest"));
            rejects += deny("unexpected-test", head, dir);
            Files.writeString(file, valid.replace("<testcase classname", "<testcase><testcase classname")
                    .replace("</testsuite>", "</testcase></testsuite>"));
            rejects += deny("nested-test", head, dir);
            Files.writeString(file, valid.replace("<testcase classname",
                    "<testcase><failure/></testcase><testcase classname"));
            rejects += deny("failed-test", head, dir);
            Files.writeString(file, "<!DOCTYPE testsuite [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + valid);
            rejects += deny("XXE", head, dir);
            Files.writeString(file, "x".repeat(1_048_577));
            rejects += deny("oversized-report", head, dir);
            Files.delete(file);
            Path target = Files.createTempFile("atto-demo-junit-target-", ".xml");
            try {
                Files.writeString(target, valid);
                Files.createSymbolicLink(file, target);
                rejects += deny("symlink", head, dir);
            } catch (java.io.IOException | UnsupportedOperationException | SecurityException unsupported) {
                // Unsupported symlinks are not counted as a passed mutation.
            } finally {
                Files.deleteIfExists(file);
                Files.deleteIfExists(target);
            }
            System.out.println("ATTO_DEMO_JUNIT_RECEIPT_HOST_SELF_TEST_PASS valid=1 rejects="
                    + rejects + " NOT_EXECUTED=compiler_guest");
        } finally {
            Files.deleteIfExists(file);
            Files.deleteIfExists(dir);
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && "--self-test".equals(args[0])) {
            selfTest();
            return;
        }
        require(args.length == 2, "usage: GIT_HEAD SUREFIRE_DIRECTORY or --self-test");
        int tests = verify(args[0], Path.of(args[1]));
        System.out.println("ATTO_DEMO_SEVEN_LINKED_GUEST_PASS head=" + args[0]
                + " tests=" + tests + " JIT_ONLY_NOT_AOT");
    }
}
