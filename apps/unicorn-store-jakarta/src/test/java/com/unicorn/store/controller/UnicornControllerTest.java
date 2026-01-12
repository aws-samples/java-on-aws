package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("UnicornController Tests")
class UnicornControllerTest {

    @Mock
    private UnicornService unicornService;

    @InjectMocks
    private UnicornController unicornController;

    private Unicorn testUnicorn;

    @BeforeEach
    void setUp() {
        testUnicorn = new Unicorn();
        testUnicorn.setId("ctrl-test-123");
        testUnicorn.setName("Controller Unicorn");
        testUnicorn.setAge("3");
        testUnicorn.setSize("Large");
        testUnicorn.setType("Fire");
    }

    @Test
    @DisplayName("Should return all unicorns as JSON")
    void shouldReturnAllUnicornsAsJson() {
        when(unicornService.getAllUnicorns()).thenReturn(Arrays.asList(testUnicorn));

        String result = unicornController.getAllUnicorns();

        assertNotNull(result);
        assertTrue(result.contains("Controller Unicorn"));
        assertTrue(result.contains("ctrl-test-123"));
        verify(unicornService, times(1)).getAllUnicorns();
    }

    @Test
    @DisplayName("Should return empty array when no unicorns")
    void shouldReturnEmptyArrayWhenNoUnicorns() {
        when(unicornService.getAllUnicorns()).thenReturn(Collections.emptyList());

        String result = unicornController.getAllUnicorns();

        assertNotNull(result);
        assertEquals("[]", result);
        verify(unicornService, times(1)).getAllUnicorns();
    }

    @Test
    @DisplayName("Should get unicorn by ID")
    void shouldGetUnicornById() {
        when(unicornService.getUnicorn("ctrl-test-123")).thenReturn(testUnicorn);

        Unicorn result = unicornController.getUnicorn("ctrl-test-123");

        assertNotNull(result);
        assertEquals("ctrl-test-123", result.getId());
        assertEquals("Controller Unicorn", result.getName());
        verify(unicornService, times(1)).getUnicorn("ctrl-test-123");
    }

    @Test
    @DisplayName("Should create unicorn")
    void shouldCreateUnicorn() {
        when(unicornService.createUnicorn(any(Unicorn.class))).thenReturn(testUnicorn);

        Unicorn result = unicornController.createUnicorn(testUnicorn);

        assertNotNull(result);
        assertEquals("Controller Unicorn", result.getName());
        verify(unicornService, times(1)).createUnicorn(testUnicorn);
    }

    @Test
    @DisplayName("Should update unicorn")
    void shouldUpdateUnicorn() {
        when(unicornService.updateUnicorn(any(Unicorn.class), eq("ctrl-test-123"))).thenReturn(testUnicorn);

        Unicorn result = unicornController.updateUnicorn("ctrl-test-123", testUnicorn);

        assertNotNull(result);
        assertEquals("ctrl-test-123", result.getId());
        verify(unicornService, times(1)).updateUnicorn(any(Unicorn.class), eq("ctrl-test-123"));
    }

    @Test
    @DisplayName("Should delete unicorn")
    void shouldDeleteUnicorn() {
        doNothing().when(unicornService).deleteUnicorn("ctrl-test-123");

        unicornController.deleteUnicorn("ctrl-test-123");

        verify(unicornService, times(1)).deleteUnicorn("ctrl-test-123");
    }
}
