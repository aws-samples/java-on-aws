package com.example.assistant;

import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.stereotype.Service;

@Service
public class DateTimeService {

    @Tool(description = """
        Get the current date and time in the specified timezone.
        Requires: timeZone - A valid timezone ID (e.g., 'UTC', 'America/New_York', 'Europe/London').
        Returns: The current date and time in ISO format (YYYY-MM-DDTHH:MM:SS).
        Errors: ILLEGAL_ARGUMENT if the timezone ID is invalid.
        Note: For future dates, use getCurrentDateTime and calculate the future date based on the current date.
        """)
    public String getCurrentDateTime(String timeZone) {
        return java.time.ZonedDateTime.now(java.time.ZoneId.of(timeZone))
                .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
}
