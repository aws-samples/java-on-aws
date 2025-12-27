package com.unicorn.store.controller;

import com.unicorn.store.service.ThreadGeneratorService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/threads")
public class ThreadManagementController {

    private final ThreadGeneratorService threadGeneratorService;

    public ThreadManagementController(ThreadGeneratorService threadGeneratorService) {
        this.threadGeneratorService = threadGeneratorService;
    }

    @PostMapping("/start")
    public ResponseEntity<String> startThreads(@RequestParam(defaultValue = "500") int count) {
        var result = tryStartThreads(count);
        if (result instanceof Success success) {
            return ResponseEntity.ok(success.message());
        } else if (result instanceof Failure failure) {
            return ResponseEntity.badRequest().body(failure.error());
        }
        return ResponseEntity.internalServerError().body("Unknown result type");
    }

    @PostMapping("/stop")
    public ResponseEntity<String> stopThreads() {
        var result = tryStopThreads();
        if (result instanceof Success success) {
            return ResponseEntity.ok(success.message());
        } else if (result instanceof Failure failure) {
            return ResponseEntity.badRequest().body(failure.error());
        }
        return ResponseEntity.internalServerError().body("Unknown result type");
    }

    @GetMapping("/count")
    public ResponseEntity<Integer> getThreadCount() {
        return ResponseEntity.ok(threadGeneratorService.getActiveThreadCount());
    }

    private Result tryStartThreads(int count) {
        try {
            threadGeneratorService.startThreads(count);
            return new Success("Successfully started " + count + " threads");
        } catch (IllegalStateException e) {
            return new Failure(e.getMessage());
        }
    }

    private Result tryStopThreads() {
        try {
            threadGeneratorService.stopThreads();
            return new Success("Successfully stopped all threads");
        } catch (IllegalStateException e) {
            return new Failure(e.getMessage());
        }
    }

    private interface Result {}
    private record Success(String message) implements Result {}
    private record Failure(String error) implements Result {}
}