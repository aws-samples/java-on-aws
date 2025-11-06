package com.example.ai.agent.tool;

import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.stereotype.Service;

@Service
public class DateTimeService {

    @Tool(description = """
        Get the current date and time in the specified timezone.
        Requires: timeZone - A valid timezone ID (e.g., 'UTC', 'America/New_York', 'Europe/London').
        Returns: The current date and time in ISO format (YYYY-MM-DDTHH:MM:SS).
        
        IMPORTANT: When users mention relative dates like "next week", "next Monday", "tomorrow":
        1. Call this tool FIRST to get today's date
        2. Calculate the specific dates based on today
        3. Use the calculated specific dates for all subsequent tool calls
        
        Example: If user says "next week Monday to Friday":
        - Call getCurrentDateTime to get today (e.g., 2025-11-06)
        - Calculate next Monday (2025-11-11) and Friday (2025-11-15)
        - Use these specific dates for flight/hotel searches
        """)
    public String getCurrentDateTime(String timeZone) {
        return java.time.ZonedDateTime.now(java.time.ZoneId.of(timeZone))
                .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }

}
