package dev.oreslang;

import dev.oreslang.runtime.ExecutionProfile;
import dev.oreslang.runtime.HotReloadManager;
import dev.oreslang.runtime.IsolatePolicy;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

final class SecureJitHotReloadDomainTest {
    private static final String NOOP = """
            pub routine main(): void {
              return;
            }
            """;

    @Test
    void supervisorLoaderAuthorityIsNeverInheritedByGuestGeneration() {
        IsolatePolicy supervisor = IsolatePolicy.developer();
        IsolatePolicy requestedGuest = IsolatePolicy.developer();

        try (HotReloadManager hot = new HotReloadManager(
                supervisor,
                requestedGuest,
                ExecutionProfile.serverJit(),
                HotReloadManager.ExecutionDomain.TRUSTED_JIT)) {
            assertTrue(hot.supervisorPolicy().allows(IsolatePolicy.Capability.HOT_CODE_LOAD));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.HOT_CODE_LOAD));
            assertEquals(HotReloadManager.ExecutionDomain.TRUSTED_JIT, hot.executionDomain());
        }
    }

    @Test
    void untrustedJitDomainFailsClosedEvenWhenSupervisorIsPrivileged() {
        IsolatePolicy privilegedGuestRequest = IsolatePolicy.developer().withCapabilities(
                IsolatePolicy.Capability.FFI,
                IsolatePolicy.Capability.NATIVE,
                IsolatePolicy.Capability.REFLECTION,
                IsolatePolicy.Capability.THREAD_CREATE,
                IsolatePolicy.Capability.POLYGLOT,
                IsolatePolicy.Capability.JAVA_INTEROP,
                IsolatePolicy.Capability.JAVA_SOURCE_INTEROP,
                IsolatePolicy.Capability.NETWORK,
                IsolatePolicy.Capability.FILESYSTEM_READ,
                IsolatePolicy.Capability.FILESYSTEM_WRITE,
                IsolatePolicy.Capability.ENVIRONMENT);

        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                privilegedGuestRequest,
                ExecutionProfile.serverJit(),
                HotReloadManager.ExecutionDomain.UNTRUSTED_JIT)) {
            assertTrue(hot.guestPolicy().adversarial());
            assertTrue(hot.guestPolicy().capabilities().isEmpty(),
                    "untrusted hot-loaded code gets no ambient authority");
            assertTrue(hot.guestPolicy().maxHeapBytes()
                    <= IsolatePolicy.strictFaas().maxHeapBytes());
            assertTrue(hot.guestPolicy().maxWallTime().compareTo(
                    IsolatePolicy.strictFaas().maxWallTime()) <= 0);
        }
    }

    @Test
    void isolatedJitStripsNativeReflectionThreadAndJavaEscapeHatches() {
        IsolatePolicy requested = IsolatePolicy.developer().withCapabilities(
                IsolatePolicy.Capability.FFI,
                IsolatePolicy.Capability.NATIVE,
                IsolatePolicy.Capability.REFLECTION,
                IsolatePolicy.Capability.THREAD_CREATE,
                IsolatePolicy.Capability.POLYGLOT,
                IsolatePolicy.Capability.JAVA_INTEROP,
                IsolatePolicy.Capability.JAVA_SOURCE_INTEROP);

        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                requested,
                ExecutionProfile.serverJit(),
                HotReloadManager.ExecutionDomain.ISOLATED_JIT)) {
            assertTrue(hot.guestPolicy().adversarial());
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.FFI));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.NATIVE));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.REFLECTION));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.THREAD_CREATE));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.POLYGLOT));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.JAVA_INTEROP));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.JAVA_SOURCE_INTEROP));
            assertFalse(hot.guestPolicy().allows(IsolatePolicy.Capability.HOT_CODE_LOAD));
        }
    }

    @Test
    void jitDomainRejectsAotOnlyExecutionProfile() {
        assertThrows(IllegalArgumentException.class, () -> new HotReloadManager(
                IsolatePolicy.developer(),
                IsolatePolicy.developer(),
                ExecutionProfile.mobileAot(ExecutionProfile.Platform.IOS),
                HotReloadManager.ExecutionDomain.TRUSTED_JIT));
    }

    @Test
    void activationDrainsPinnedOldGenerationAndReclaimsAfterLeaseRelease() {
        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit())) {
            HotReloadManager.Generation first = hot.loadAndStart("service.ores", NOOP);
            HotReloadManager.GenerationLease lease = hot.pinActive("service.ores");

            HotReloadManager.Generation second = hot.load("service.ores", """
                    pub routine main(): void {
                      val version = 2;
                      return;
                    }
                    """);
            second.start();
            second.activate();

            assertEquals(second.id(), hot.active("service.ores").id());
            assertEquals(HotReloadManager.GenerationState.DRAINING, first.state());
            assertFalse(first.closed());
            assertEquals(1, first.pinCount());

            HotReloadManager.GenerationLease childLease = lease.retain();
            assertEquals(first.id(), childLease.generationId());
            assertEquals(2, first.pinCount());

            lease.close();
            assertEquals(1, first.pinCount());
            assertFalse(first.closed());

            childLease.close();
            assertTrue(first.closed());
            assertEquals(1, hot.liveGenerations());
        }
    }

    @Test
    void closeDrainsPinnedGenerationsInsteadOfTearingContextsDownEarly() {
        HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit());
        HotReloadManager.Generation generation = hot.loadAndStart("service.ores", NOOP);
        HotReloadManager.GenerationLease lease = hot.pinActive("service.ores");

        hot.close();

        assertEquals(HotReloadManager.GenerationState.DRAINING, generation.state());
        assertFalse(generation.closed());
        assertEquals(1, hot.liveGenerations());
        assertThrows(IllegalStateException.class, () -> hot.load("other.ores", NOOP));

        lease.close();

        assertTrue(generation.closed());
        assertEquals(0, hot.liveGenerations());
        hot.close();
    }

    @Test
    void failedStagedGenerationNeverDisplacesHealthyActiveGeneration() {
        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit())) {
            HotReloadManager.Generation healthy = hot.loadAndStart("service.ores", NOOP);

            HotReloadManager.Generation broken = hot.load("service.ores", """
                    pub routine main(): void {
                      val values = arr[1];
                      val boom = values[99];
                      return;
                    }
                    """);

            assertThrows(RuntimeException.class, broken::start);
            assertEquals(healthy.id(), hot.active("service.ores").id());
            assertEquals(HotReloadManager.GenerationState.ACTIVE, healthy.state());
            assertTrue(broken.closed());
        }
    }
}
