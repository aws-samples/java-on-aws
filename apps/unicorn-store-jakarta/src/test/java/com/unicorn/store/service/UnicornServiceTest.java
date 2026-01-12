package com.unicorn.store.service;

import com.unicorn.store.data.UnicornPublisher;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("UnicornService Tests")
class UnicornServiceTest {

    @Mock
    private UnicornRepository unicornRepository;

    @Mock
    private UnicornPublisher unicornPublisher;

    @InjectMocks
    private UnicornService unicornService;

    private Unicorn testUnicorn;

    @BeforeEach
    void setUp() {
        testUnicorn = new Unicorn();
        testUnicorn.setId("test-id-123");
        testUnicorn.setName("Sparkle");
        testUnicorn.setAge("5");
        testUnicorn.setSize("Medium");
        testUnicorn.setType("Rainbow");
    }

    @Test
    @DisplayName("Should return all unicorns")
    void shouldReturnAllUnicorns() {
        Unicorn unicorn2 = new Unicorn();
        unicorn2.setId("test-id-456");
        unicorn2.setName("Thunder");

        when(unicornRepository.findAll()).thenReturn(Arrays.asList(testUnicorn, unicorn2));

        List<Unicorn> result = unicornService.getAllUnicorns();

        assertEquals(2, result.size());
        assertEquals("Sparkle", result.get(0).getName());
        assertEquals("Thunder", result.get(1).getName());
        verify(unicornRepository, times(1)).findAll();
    }

    @Test
    @DisplayName("Should return empty list when no unicorns exist")
    void shouldReturnEmptyListWhenNoUnicorns() {
        when(unicornRepository.findAll()).thenReturn(Arrays.asList());

        List<Unicorn> result = unicornService.getAllUnicorns();

        assertTrue(result.isEmpty());
        verify(unicornRepository, times(1)).findAll();
    }

    @Test
    @DisplayName("Should get unicorn by ID")
    void shouldGetUnicornById() {
        when(unicornRepository.findById("test-id-123")).thenReturn(testUnicorn);

        Unicorn result = unicornService.getUnicorn("test-id-123");

        assertNotNull(result);
        assertEquals("test-id-123", result.getId());
        assertEquals("Sparkle", result.getName());
        verify(unicornRepository, times(1)).findById("test-id-123");
    }

    @Test
    @DisplayName("Should create unicorn and publish event")
    void shouldCreateUnicornAndPublishEvent() {
        when(unicornRepository.insert(any(Unicorn.class))).thenReturn(testUnicorn);

        Unicorn result = unicornService.createUnicorn(testUnicorn);

        assertNotNull(result);
        assertEquals("Sparkle", result.getName());
        verify(unicornRepository, times(1)).insert(testUnicorn);
        verify(unicornPublisher, times(1)).publish(testUnicorn, UnicornEventType.UNICORN_CREATED);
    }

    @Test
    @DisplayName("Should update unicorn and publish event")
    void shouldUpdateUnicornAndPublishEvent() {
        when(unicornRepository.update(any(Unicorn.class), eq("test-id-123"))).thenReturn(testUnicorn);

        Unicorn result = unicornService.updateUnicorn(testUnicorn, "test-id-123");

        assertNotNull(result);
        assertEquals("Sparkle", result.getName());
        verify(unicornRepository, times(1)).update(testUnicorn, "test-id-123");
        verify(unicornPublisher, times(1)).publish(testUnicorn, UnicornEventType.UNICORN_UPDATED);
    }

    @Test
    @DisplayName("Should delete unicorn and publish event")
    void shouldDeleteUnicornAndPublishEvent() {
        when(unicornRepository.findById("test-id-123")).thenReturn(testUnicorn);
        doNothing().when(unicornRepository).delete("test-id-123");

        unicornService.deleteUnicorn("test-id-123");

        verify(unicornRepository, times(1)).findById("test-id-123");
        verify(unicornRepository, times(1)).delete("test-id-123");
        verify(unicornPublisher, times(1)).publish(testUnicorn, UnicornEventType.UNICORN_DELETED);
    }

    @Test
    @DisplayName("Should handle publisher exception gracefully")
    void shouldHandlePublisherExceptionGracefully() {
        when(unicornRepository.insert(any(Unicorn.class))).thenReturn(testUnicorn);
        doThrow(new RuntimeException("Publisher error")).when(unicornPublisher)
            .publish(any(Unicorn.class), any(UnicornEventType.class));

        Unicorn result = unicornService.createUnicorn(testUnicorn);

        assertNotNull(result);
        assertEquals("Sparkle", result.getName());
        verify(unicornRepository, times(1)).insert(testUnicorn);
    }
}
