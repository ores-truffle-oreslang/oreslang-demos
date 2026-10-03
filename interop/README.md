# Java / Oreslang interop demos

This folder deliberately demonstrates two different interoperability boundaries.

## 1. Oreslang inside a `.java` file — in-process

`JavaEmbedsOreslang.java` embeds the Oreslang source in a Java text block:

```java
String oreslang = """
    define module embedded_math
      pub fnc twice(int value) => int {
        return value * 2;
      }
    end

    pub routine main() => void {
      stdio.println(embedded_math.twice(21));
      return;
    }
    """;
```

Java builds a Graal `Source`, evaluates it through `Context`, captures the Oreslang output, and verifies that the guest produced `42`.

Run with a local Oreslang source checkout:

```bash
ORESLANG_SOURCE_DIR=../oreslang-source.java ./run-java-embeds-oreslang.sh
```

Or set `ORESLANG_CLASSPATH` to an already-built Oreslang + Graal runtime classpath.

## 2. Java inside a `.ores` file — build-time/codegen

`OreslangEmbedsJava.ores` owns Java source text and emits a complete Java source file. The run script executes Oreslang, captures that generated Java, and launches it using Java source-file mode:

```bash
./run-oreslang-embeds-java.sh
```

Expected output:

```text
42
```

This is intentionally described as code-generation interop. The current runtime denies unrestricted Java host objects and reflection. A future direct Oreslang -> Java call surface should be capability-gated and expose only host-provided bindings/methods, especially so untrusted actors cannot acquire ambient JVM authority.
