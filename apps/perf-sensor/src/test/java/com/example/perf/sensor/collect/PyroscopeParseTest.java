package com.example.perf.sensor.collect;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pyroscope {@code /pyroscope/render} flamebearer reduction: self time per leaf, whole-profile
 * shares that do not depend on how many frames are returned, and the tick -> sample conversion.
 */
class PyroscopeParseTest {

    private static final JsonMapper MAPPER = JsonMapper.builder().build();

    // levels: groups of 4 = [offset, total, self, nameIdx]. Names: 0 root, 1 app, 2 GC, 3 JIT, 4 park.
    // Self ticks (ns): app 0.5 s, GC 0.2 s, JIT 0.1 s, park 0.2 s -> numTicks 1 s = 1e9 (100 samples at 10 ms).
    private static final String BODY = """
        {"flamebearer":{"names":["total","com/example/shop/Service.run","G1YoungCollector::collect",
                                 "Compile::Code_Gen","jdk/internal/misc/Unsafe.park"],
                        "levels":[[0,1000000000,0,0],
                                  [0,500000000,500000000,1, 0,200000000,200000000,2, 0,100000000,100000000,3, 0,200000000,200000000,4]],
                        "numTicks":1000000000},
         "metadata":{"sampleRate":1000000000}}
        """;

    @Test
    void sharesAreOverTheWholeProfile_notOnlyTheReturnedFrames() throws Exception {
        var all = PyroscopeClient.parse(MAPPER.readTree(BODY), 15);
        var one = PyroscopeClient.parse(MAPPER.readTree(BODY), 1);
        assertThat(all.frames()).hasSize(4);
        assertThat(one.frames()).hasSize(1);
        assertThat(one.frames().getFirst().name()).isEqualTo("com/example/shop/Service.run");
        // GC 20 %, JIT 10 %, park 20 % — identical whether 1 or 15 frames are returned.
        assertThat(all.gcShare()).isEqualTo(20.0);
        assertThat(all.jitShare()).isEqualTo(10.0);
        assertThat(all.futexShare()).isEqualTo(20.0);
        assertThat(one.gcShare()).isEqualTo(20.0);
        assertThat(one.jitShare()).isEqualTo(10.0);
        assertThat(one.futexShare()).isEqualTo(20.0);
    }

    @Test
    void ticksBecomeSamplesViaSampleRate() throws Exception {
        var d = PyroscopeClient.parse(MAPPER.readTree(BODY), 15);
        assertThat(d.samples()).isEqualTo(100);   // 1e9 ns / 1e9 per s = 1 s x 100 samples per s
        assertThat(d.frames().getFirst().selfPct()).isEqualTo(50.0);
    }

    @Test
    void emptyProfile_hasNoShares() throws Exception {
        var d = PyroscopeClient.parse(MAPPER.readTree("{\"flamebearer\":{\"numTicks\":0}}"), 15);
        assertThat(d.hasSamples()).isFalse();
        assertThat(d.jitShare()).isNull();
    }
}
