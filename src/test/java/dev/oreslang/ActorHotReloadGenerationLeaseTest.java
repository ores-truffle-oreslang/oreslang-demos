package dev.oreslang;

import dev.oreslang.runtime.ActorRuntime;
import dev.oreslang.runtime.ExecutionProfile;
import dev.oreslang.runtime.HotReloadManager;
import dev.oreslang.runtime.IsolatePolicy;
import org.junit.jupiter.api.Test;

import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

import static org.junit.jupiter.api.Assertions.*;

final class ActorHotReloadGenerationLeaseTest {
    private static final String NOOP = """
            pub routine main(): void {
              return;
            }
            """;

    @Test
    void supervisorSpawnsPinActiveGenerationAndChildSpawnsInheritDrainingParent() throws Exception {
        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit())) {
            HotReloadManager.Generation first = hot.loadAndStart("service.ores", NOOP);

            try (ActorRuntime runtime = new ActorRuntime(
                    IsolatePolicy.developer(),
                    ActorRuntime.DispatcherConfig.defaults(),
                    ActorRuntime.TurnExecutor.direct(),
                    hot,
                    "service.ores")) {
                ActorRuntime.ActorRef<String> parent = runtime.spawnPrivate(
                        ignored -> (message, turn) -> {
                            if ("spawn-child".equals(message)) {
                                turn.runtime().spawnPrivate(
                                        childContext -> (childMessage, childTurn) -> { });
                            }
                        });

                assertEquals(1, first.pinCount(),
                        "root actor lifetime must pin the active generation immediately");

                HotReloadManager.Generation second = hot.load("service.ores", """
                        pub routine main(): void {
                          val version = 2;
                          return;
                        }
                        """);
                second.start();
                second.activate();

                assertEquals(HotReloadManager.GenerationState.DRAINING, first.state());
                assertEquals(1, first.pinCount());

                parent.send("spawn-child");
                awaitCondition(() -> runtime.actorCount() == 2 && first.pinCount() == 2);

                assertEquals(2, first.pinCount(),
                        "child spawned by a draining actor must retain the parent's generation");

                ActorRuntime.ActorRef<String> newRoot = runtime.spawnPrivate(
                        ignored -> (message, turn) -> { });
                assertEquals(1, second.pinCount(),
                        "new supervisor work after activation must pin the new generation");

                newRoot.stop();
                assertEquals(0, second.pinCount());
                assertEquals(HotReloadManager.GenerationState.ACTIVE, second.state());

                parent.stop();
                awaitCondition(() -> first.pinCount() == 1);
                assertFalse(first.closed(),
                        "the inherited child lease must keep the draining generation alive");

                runtime.close();
                awaitCondition(first::closed);
                assertEquals(1, hot.liveGenerations());
                assertEquals(second.id(), hot.active("service.ores").id());
            }
        }
    }

    @Test
    void managerCloseWaitsForActorLifetimeLease() throws Exception {
        HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit());
        HotReloadManager.Generation generation = hot.loadAndStart("service.ores", NOOP);
        ActorRuntime runtime = new ActorRuntime(
                IsolatePolicy.developer(),
                ActorRuntime.DispatcherConfig.defaults(),
                ActorRuntime.TurnExecutor.direct(),
                hot,
                "service.ores");
        try {
            runtime.spawnPrivate(ignored -> (message, turn) -> { });
            assertEquals(1, generation.pinCount());

            hot.close();

            assertEquals(HotReloadManager.GenerationState.DRAINING, generation.state());
            assertFalse(generation.closed(),
                    "manager shutdown must not invalidate code under a live actor");

            runtime.close();
            awaitCondition(generation::closed);
            assertEquals(0, hot.liveGenerations());
        } finally {
            try {
                runtime.close();
            } finally {
                hot.close();
            }
        }
    }

    @Test
    void boundRuntimeRejectsSpawnWhenNoGenerationIsActiveWithoutLeakingActorQuota() {
        try (HotReloadManager hot = new HotReloadManager(
                IsolatePolicy.developer(),
                ExecutionProfile.serverJit());
             ActorRuntime runtime = new ActorRuntime(
                     IsolatePolicy.developer(),
                     ActorRuntime.DispatcherConfig.defaults(),
                     ActorRuntime.TurnExecutor.direct(),
                     hot,
                     "service.ores")) {
            hot.load("service.ores", NOOP);

            assertThrows(IllegalStateException.class,
                    () -> runtime.spawnPrivate(ignored -> (message, turn) -> { }));
            assertEquals(0, runtime.actorCount());
        }
    }

    private static void awaitCondition(BooleanSupplier condition) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
        while (!condition.getAsBoolean() && System.nanoTime() < deadline) {
            Thread.sleep(5);
        }
        assertTrue(condition.getAsBoolean(), "condition did not become true before timeout");
    }
}
