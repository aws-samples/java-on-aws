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
        try {
            threadGeneratorService.startThreads(count);
            return ResponseEntity.ok("Successfully started " + count + " threads");
        } catch (IllegalStateException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/stop")
    public ResponseEntity<String> stopThreads() {
        try {
            threadGeneratorService.stopThreads();
            return ResponseEntity.ok("Successfully stopped all threads");
        } catch (IllegalStateException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @GetMapping("/count")
    public ResponseEntity<Integer> getThreadCount() {
        return ResponseEntity.ok(threadGeneratorService.getActiveThreadCount());
    }
}
