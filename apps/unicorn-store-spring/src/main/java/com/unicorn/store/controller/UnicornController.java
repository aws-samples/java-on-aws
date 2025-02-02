package com.unicorn.store.controller;

import com.unicorn.store.exceptions.ResourceNotFoundException;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;

import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@Validated
public class UnicornController {
    private final UnicornService unicornService;
    private static final Logger logger = LoggerFactory.getLogger(UnicornController.class);

    private static final String UNICORN_NOT_FOUND = "Unicorn not found with ID: %s";

    public UnicornController(UnicornService unicornService) {
        this.unicornService = unicornService;
    }

    @PostMapping("/unicorns")
    public ResponseEntity<Unicorn> createUnicorn(@Valid @RequestBody Unicorn unicorn) {
        try {
            logger.debug("Creating unicorn: {}", unicorn);
            var savedUnicorn = unicornService.createUnicorn(unicorn);
            logger.info("Successfully created unicorn with ID: {}", savedUnicorn.getId());
            return ResponseEntity
                    .status(HttpStatus.CREATED)
                    .body(savedUnicorn);
        } catch (IllegalArgumentException e) {
            logger.warn("Invalid unicorn data: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage(), e);
        } catch (Exception e) {
            logger.error("Failed to create unicorn", e);
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR, "Failed to create unicorn", e);
        }
    }

    @GetMapping("/unicorns")
    public ResponseEntity<List<Unicorn>> getAllUnicorns() {
        try {
            logger.debug("Retrieving all unicorns");
            var unicorns = unicornService.getAllUnicorns();

            if (unicorns.isEmpty()) {
                logger.info("No unicorns found");
                return ResponseEntity.noContent().build();
            }

            logger.info("Retrieved {} unicorns", unicorns.size());
            return ResponseEntity.ok(unicorns);
        } catch (Exception e) {
            logger.error("Failed to retrieve unicorns", e);
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR, "Failed to retrieve unicorns", e);
        }
    }

    @PutMapping("/unicorns/{unicornId}")
    public ResponseEntity<Unicorn> updateUnicorn(
            @PathVariable String unicornId,
            @Valid @RequestBody Unicorn unicorn) {
        try {
            logger.debug("Updating unicorn with ID: {}", unicornId);
            var updatedUnicorn = unicornService.updateUnicorn(unicorn, unicornId);
            logger.info("Successfully updated unicorn with ID: {}", unicornId);
            return ResponseEntity.ok(updatedUnicorn);
        } catch (ResourceNotFoundException e) {
            logger.warn("Unicorn not found with ID: {}", unicornId);
            throw new ResponseStatusException(NOT_FOUND,
                    String.format(UNICORN_NOT_FOUND, unicornId), e);
        } catch (IllegalArgumentException e) {
            logger.warn("Invalid update data for unicorn ID {}: {}", unicornId, e.getMessage());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage(), e);
        } catch (Exception e) {
            logger.error("Failed to update unicorn with ID: {}", unicornId, e);
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR,
                    "Failed to update unicorn", e);
        }
    }

    @GetMapping("/unicorns/{unicornId}")
    public ResponseEntity<Unicorn> getUnicorn(@PathVariable String unicornId) {
        try {
            logger.debug("Retrieving unicorn with ID: {}", unicornId);
            var unicorn = unicornService.getUnicorn(unicornId);
            logger.info("Successfully retrieved unicorn with ID: {}", unicornId);
            return ResponseEntity.ok(unicorn);
        } catch (ResourceNotFoundException e) {
            logger.warn("Unicorn not found with ID: {}", unicornId);
            throw new ResponseStatusException(NOT_FOUND,
                    String.format(UNICORN_NOT_FOUND, unicornId), e);
        } catch (Exception e) {
            logger.error("Failed to retrieve unicorn with ID: {}", unicornId, e);
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR,
                    "Failed to retrieve unicorn", e);
        }
    }

    @DeleteMapping("/unicorns/{unicornId}")
    public ResponseEntity<String> deleteUnicorn(@PathVariable String unicornId) {
        try {
            logger.debug("Deleting unicorn with ID: {}", unicornId);
            unicornService.deleteUnicorn(unicornId);
            logger.info("Successfully deleted unicorn with ID: {}", unicornId);
            return ResponseEntity.ok().build();
        } catch (ResourceNotFoundException e) {
            logger.warn("Unicorn not found with ID: {}", unicornId);
            throw new ResponseStatusException(NOT_FOUND,
                    String.format(UNICORN_NOT_FOUND, unicornId), e);
        } catch (Exception e) {
            logger.error("Failed to delete unicorn with ID: {}", unicornId, e);
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR,
                    "Failed to delete unicorn", e);
        }
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, List<String>>> handleValidationErrors(
            MethodArgumentNotValidException ex) {
        List<String> errors = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.toList());

        logger.warn("Validation failed: {}", errors);
        return ResponseEntity
                .badRequest()
                .body(Collections.singletonMap("errors", errors));
    }

    @GetMapping("/")
    public ResponseEntity<String> getWelcomeMessage() {
        return new ResponseEntity<>("Welcome to the Unicorn Store!", HttpStatus.OK);
    }
}
