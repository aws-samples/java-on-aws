package com.unicorn.agent;

import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;

class DateTimeTools {

    @Tool(description = "Get the current date and time")
    public String getCurrentDateTime(String timeZone) {
        return java.time.ZonedDateTime.now(java.time.ZoneId.of(timeZone))
                .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }

}