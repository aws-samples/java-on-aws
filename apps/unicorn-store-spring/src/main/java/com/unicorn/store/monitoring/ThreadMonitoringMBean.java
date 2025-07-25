package com.unicorn.store.monitoring;

import com.unicorn.store.service.ThreadGeneratorService;
import org.springframework.jmx.export.annotation.ManagedAttribute;
import org.springframework.jmx.export.annotation.ManagedResource;
import org.springframework.stereotype.Component;

@Component
@ManagedResource(objectName = "com.unicorn.store:type=ThreadMonitoring,name=ThreadStats")
public class ThreadMonitoringMBean {

    private final ThreadGeneratorService threadGeneratorService;

    public ThreadMonitoringMBean(ThreadGeneratorService threadGeneratorService) {
        this.threadGeneratorService = threadGeneratorService;
    }

    @ManagedAttribute(description = "Number of active custom threads")
    public int getActiveThreadCount() {
        return threadGeneratorService.getActiveThreadCount();
    }
}
