#!/bin/bash
# Prints a date of Alice's trip relative to today:
#   TRIP_START=$(~/workshop/scripts/trip-dates.sh start)   # the Monday of the week two months from now
#   TRIP_END=$(~/workshop/scripts/trip-dates.sh end)       # the Saturday after it
# Rule (the same in the travel portal and the calendar API): the Monday of the week that contains today plus two
# calendar months (the last day of the month when the day does not exist), back on Saturday.
case "${1:-}" in
  start) offset=0 ;;
  end) offset=5 ;;
  *) echo "usage: trip-dates.sh start|end" >&2; exit 2 ;;
esac
python3 - "${offset}" <<'PY'
import calendar
import sys
from datetime import date, timedelta

today = date.today()
month = today.month + 2
year, month = today.year + (month - 1) // 12, (month - 1) % 12 + 1
start = date(year, month, min(today.day, calendar.monthrange(year, month)[1]))
start -= timedelta(days=start.weekday())
print((start + timedelta(days=int(sys.argv[1]))).isoformat())
PY
