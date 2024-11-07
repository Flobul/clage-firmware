#! /bin/sh
echo "`sqlite3 -header -separator ';' /var/run/chsd/chsd.sqlite "SELECT DISTINCT l.id, uid AS deviceId, radioId, radioAddress, enabled, datetime(usageTime,'unixepoch', 'localtime') AS usageDateTime, usageDuration, powerConsumption, waterConsumption FROM logs AS l,devices AS d WHERE (d.id = l.device_id) ORDER BY l.id;"`"
exit 0
