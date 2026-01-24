package com.example.agent;

import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

class DateTimeTools {

    @Tool(description = """
        Get the current date and time in a specific time zone.
        Use for answering questions requiring date time knowledge,
        like today, tomorrow, next week, next month.
        """)
    public String getCurrentDateTime(
            @ToolParam(description = "Time zone ID, e.g. Europe/Paris, America/New_York, UTC")
            String timeZone) {
        return ZonedDateTime.now(ZoneId.of(timeZone))
            .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
}
