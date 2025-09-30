package com.unicorn.jvm;

import one.convert.Arguments;
import one.convert.FlameGraph;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

@Component
public class FlameGraphConverter {

    public String convertToFlameGraph(String collapsedData) throws IOException {
        Path tempDir = Files.createTempDirectory("flamegraph_");
        Path inputFile = tempDir.resolve("collapsed.txt");
        Path outputFile = tempDir.resolve("flamegraph.html");

        try {
            Files.write(inputFile, collapsedData.getBytes());

            Arguments args = new Arguments();
            args.output = "html";
            FlameGraph.convert(inputFile.toString(), outputFile.toString(), args);

            if (Files.exists(outputFile)) {
                return Files.readString(outputFile);
            }
            throw new RuntimeException("Flamegraph conversion failed");
        } finally {
            Files.deleteIfExists(inputFile);
            Files.deleteIfExists(outputFile);
            Files.deleteIfExists(tempDir);
        }
    }
}