package com.example.ai.agent.tool;

import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.stereotype.Service;

@Service
public class DateTimeService {

    @Tool(description = """
        Get current date and time in specified timezone.

        Parameters:
        - timeZone: e.g., 'UTC', 'America/New_York', 'Europe/London'

        Returns: ISO format (YYYY-MM-DDTHH:MM:SS)

        Use this when users mention relative dates like "next week" or "tomorrow".
        """)
    public String getCurrentDateTime(String timeZone) {
        return ZonedDateTime.now(ZoneId.of(timeZone))
                .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
}
