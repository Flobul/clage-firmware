#!/bin/sh

. /etc/router-mqtt.conf

BASE_TELE="tele/$TOPIC"
BASE_STAT="stat/$TOPIC"
BASE_CMND="cmnd/$TOPIC"

STATE="/tmp/router-mqtt-state"
mkdir -p "$STATE"

MQTT_PUB="$(command -v mosquitto_pub 2>/dev/null)"
MQTT_SUB="$(command -v mosquitto_sub 2>/dev/null)"

[ -x "$MQTT_PUB" ] || exit 1

pub() {
        $MQTT_PUB -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$1" -m "$2" >/dev/null 2>&1
}

pubr() {
        $MQTT_PUB -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -r -t "$1" -m "$2" >/dev/null 2>&1
}

iso_time() {
        date "+%Y-%m-%dT%H:%M:%S"
}

json_escape_one() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

db_snapshot() {
        DB_LIVE="/var/run/chsd/chsd.sqlite"
        DB_SNAP="/tmp/router-mqtt-chsd.sqlite"

        [ -f "$DB_LIVE" ] || return 1

        sqlite3 "$DB_LIVE" ".backup '$DB_SNAP'" >/dev/null 2>&1 || cp "$DB_LIVE" "$DB_SNAP" 2>/dev/null
        [ -f "$DB_SNAP" ] || return 1

        return 0
}

publish_tasmota_discovery() {
        [ "$TASMOTA_DISCOVERY" = "1" ] || return

        IP="$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/ { sub("addr:","",$2); print $2 }')"
        HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
        [ -n "$IP" ] || IP="192.168.23.120"
        [ -n "$HOST" ] || HOST="$TOPIC"

        # Imitation du topic Tasmota natif :
        # tasmota/discovery/<mac>/config
        # tasmota/discovery/<mac>/sensors

        pubr "tasmota/discovery/$DISCOVERY_ID/config" "{\"ip\":\"$IP\",\"dn\":\"$FRIENDLY_NAME\",\"fn\":[\"$FRIENDLY_NAME\",null,null,null,null,null,null,null],\"hn\":\"$HOST\",\"mac\":\"$DISCOVERY_ID\",\"md\":\"CLAGE CHS / OpenWrt\",\"ty\":0,\"if\":0,\"cam\":0,\"ofln\":\"Offline\",\"onln\":\"Online\",\"state\":[\"OFF\",\"ON\",\"TOGGLE\",\"HOLD\"],\"sw\":\"chsd-1.3.1\",\"t\":\"$TOPIC\",\"ft\":\"%prefix%/%topic%/\",\"tp\":[\"cmnd\",\"stat\",\"tele\"],\"rl\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"swc\":[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],\"swn\":[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null],\"btn\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"so\":{\"4\":0,\"11\":0,\"13\":0,\"17\":0,\"20\":0,\"30\":0,\"68\":0,\"73\":0,\"82\":0,\"114\":0,\"117\":0},\"lk\":0,\"lt_st\":0,\"bat\":0,\"dslp\":0,\"sho\":[],\"sht\":[],\"ver\":1}"

        publish_tasmota_sensors_discovery
}

publish_tasmota_sensors_discovery() {
        [ "$TASMOTA_DISCOVERY" = "1" ] || return

        TX_TOTAL="$(cat /tmp/router-mqtt-state/tx_total 2>/dev/null || echo 0)"
        RX_TOTAL="$(cat /tmp/router-mqtt-state/rx_total 2>/dev/null || echo 0)"

        pubr "tasmota/discovery/$DISCOVERY_ID/sensors" "{\"sn\":{\"Time\":\"$(iso_time)\",\"CLAGE\":{\"ApiOk\":1},\"CHSD\":{\"TxTotal\":$TX_TOTAL,\"RxTotal\":$RX_TOTAL},\"TempUnit\":\"C\"},\"ver\":1}"
}

publish_commands_discovery() {
        pubr "tele/$TOPIC/COMMANDS" "{\"Commands\":[\"STATUS\",\"STATUS 0\",\"STATUS 1\",\"STATUS 2\",\"STATUS 5\",\"STATUS 8\",\"STATUS 10\",\"POLL\",\"TELEPERIOD\",\"DISCOVERY\",\"DB\",\"DBSCHEMA\",\"RESTART_CHSD\",\"RESTART_LIGHTTPD\",\"RESTART 1\",\"REBOOT 1\"],\"CommandTopic\":\"cmnd/$TOPIC/<command>\",\"ResultTopic\":\"stat/$TOPIC/RESULT\"}"
}

publish_tasmota_info() {
        IP="$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/ { sub("addr:","",$2); print $2 }')"
        HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
        UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"

        pub "tele/$TOPIC/INFO1" "{\"Info1\":{\"Module\":\"CLAGE CHS OpenWrt\",\"Version\":\"chsd-1.3.1\",\"FallbackTopic\":\"cmnd/$DISCOVERY_ID/\",\"GroupTopic\":\"cmnd/tasmotas/\"}}"
        pub "tele/$TOPIC/INFO2" "{\"Info2\":{\"WebServerMode\":\"Admin\",\"Hostname\":\"$HOST\",\"IPAddress\":\"$IP\"}}"
        pub "tele/$TOPIC/INFO3" "{\"Info3\":{\"RestartReason\":\"Software/System restart\"}}"

        pub "tele/$TOPIC/LWT" "Online"
        pub "stat/$TOPIC/STATUS" "{\"Status\":{\"Topic\":\"$TOPIC\",\"FriendlyName\":[\"$FRIENDLY_NAME\"],\"Uptime\":$UPTIME,\"IPAddress\":\"$IP\"}}"
}

publish_status_0() {
        publish_status_1
        publish_status_2
        publish_status_5
        publish_status_8
        publish_status_10
        pub "stat/$TOPIC/RESULT" "{\"Status\":\"DONE\"}"
}

publish_status_1() {
        HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
        UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
        pub "stat/$TOPIC/STATUS1" "{\"StatusPRM\":{\"Baudrate\":115200,\"GroupTopic\":\"tasmotas\",\"OtaUrl\":\"\",\"RestartReason\":\"Software/System restart\",\"Uptime\":$UPTIME,\"StartupUTC\":\"\",\"Sleep\":50,\"CfgHolder\":4617,\"BootCount\":1,\"SaveCount\":1,\"SaveAddress\":\"F4000\"},\"Hostname\":\"$HOST\"}"
}

publish_status_2() {
        IP="$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/ { sub("addr:","",$2); print $2 }')"
        pub "stat/$TOPIC/STATUS2" "{\"StatusFWR\":{\"Version\":\"chsd-1.3.1\",\"BuildDateTime\":\"2026-06-10T00:00:00\",\"Core\":\"OpenWrt Chaos Calmer 15.05.1\",\"SDK\":\"MikroTik ar71xx\"},\"StatusNET\":{\"Hostname\":\"$TOPIC\",\"IPAddress\":\"$IP\",\"DNSServer\":\"\",\"Mac\":\"$DISCOVERY_ID\",\"Webserver\":2,\"WifiConfig\":4}}"
}

publish_status_5() {
        pub "stat/$TOPIC/STATUS5" "{\"StatusNET\":{\"Hostname\":\"$TOPIC\",\"IPAddress\":\"$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/ { sub("addr:","",$2); print $2 }')\",\"Gateway\":\"\",\"Subnetmask\":\"\",\"DNSServer1\":\"\",\"DNSServer2\":\"\",\"Mac\":\"$DISCOVERY_ID\",\"Webserver\":2}}"
}

publish_status_8() {
        TX_TOTAL="$(cat /tmp/router-mqtt-state/tx_total 2>/dev/null || echo 0)"
        RX_TOTAL="$(cat /tmp/router-mqtt-state/rx_total 2>/dev/null || echo 0)"

        pub "stat/$TOPIC/STATUS8" "{\"StatusSNS\":{\"Time\":\"$(iso_time)\",\"CHSD\":{\"TxTotal\":$TX_TOTAL,\"RxTotal\":$RX_TOTAL},\"TempUnit\":\"C\"}}"
}

publish_status_10() {
        UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
        LOAD="$(cat /proc/loadavg 2>/dev/null | awk '{print $1","$2","$3}')"

        pub "stat/$TOPIC/STATUS10" "{\"StatusSNS\":{\"Time\":\"$(iso_time)\",\"Router\":{\"Uptime\":$UPTIME,\"Load\":\"$LOAD\"}}}"
}

publish_db_summary() {
        db_snapshot || {
                pub "tele/$TOPIC/DB" "{\"Time\":\"$(iso_time)\",\"DbOk\":0}"
                return
        }

        DB="/tmp/router-mqtt-chsd.sqlite"

        DEVICES_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM devices;" 2>/dev/null || echo 0)"
        LOGS_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM logs;" 2>/dev/null || echo 0)"
        TIMERS_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM timers;" 2>/dev/null || echo 0)"
        USERS_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo 0)"

        LAST_LOG="$(sqlite3 -separator '|' "$DB" \
                "SELECT d.uid,
                        d.busId,
                        ifnull(d.serial,''),
                        ifnull(d.serialPowerUnit,''),
                        ifnull(d.radioId,0),
                        ifnull(d.enabled,0),
                        ifnull(d.radioChannel,0),
                        ifnull(d.radioAddress,0),
                        ifnull(d.swVersion,''),
                        l.id,
                        l.usageTime,
                        l.usageDuration,
                        l.powerConsumption,
                        l.waterConsumption,
                        ifnull(l.customId,0),
                        ifnull(l.tap_id,0)
                 FROM logs AS l
                 JOIN devices AS d ON d.id = l.device_id
                 ORDER BY l.id DESC
                 LIMIT 1;" 2>/dev/null)"

        if [ -n "$LAST_LOG" ]; then
                OLDIFS="$IFS"
                IFS='|'
                set -- $LAST_LOG
                IFS="$OLDIFS"

                uid="$(json_escape_one "$1")"
                busId="$2"
                serial="$(json_escape_one "$3")"
                serialPowerUnit="$(json_escape_one "$4")"
                radioId="$5"
                enabled="$6"
                radioChannel="$7"
                radioAddress="$8"
                swVersion="$(json_escape_one "$9")"

                log_id="${10}"
                usage_time="${11}"
                usage_duration="${12}"
                power="${13}"
                water="${14}"
                custom_id="${15}"
                tap_id="${16}"

                pub "tele/$TOPIC/DB" "{\"Time\":\"$(iso_time)\",\"DbOk\":1,\"Counts\":{\"Devices\":$DEVICES_COUNT,\"Logs\":$LOGS_COUNT,\"Timers\":$TIMERS_COUNT,\"Users\":$USERS_COUNT},\"LastLog\":{\"DeviceUid\":\"$uid\",\"BusId\":$busId,\"Serial\":\"$serial\",\"SerialPowerUnit\":\"$serialPowerUnit\",\"RadioId\":$radioId,\"Enabled\":$enabled,\"RadioChannel\":$radioChannel,\"RadioAddress\":$radioAddress,\"SwVersion\":\"$swVersion\",\"LogId\":$log_id,\"UsageTime\":$usage_time,\"UsageDuration\":$usage_duration,\"PowerConsumption\":$power,\"WaterConsumption\":$water,\"CustomId\":$custom_id,\"TapId\":$tap_id}}"
        else
                pub "tele/$TOPIC/DB" "{\"Time\":\"$(iso_time)\",\"DbOk\":1,\"Counts\":{\"Devices\":$DEVICES_COUNT,\"Logs\":$LOGS_COUNT,\"Timers\":$TIMERS_COUNT,\"Users\":$USERS_COUNT}}"
        fi
}

publish_db_devices() {
        db_snapshot || return
        DB="/tmp/router-mqtt-chsd.sqlite"

        sqlite3 -separator '|' "$DB" \
                "SELECT id,
                        uid,
                        busId,
                        syncId,
                        ifnull(serial,''),
                        ifnull(serialPowerUnit,''),
                        ifnull(radioId,0),
                        ifnull(enabled,0),
                        ifnull(radioChannel,0),
                        ifnull(radioAddress,0),
                        ifnull(timeCreated,''),
                        ifnull(timeModified,''),
                        ifnull(swVersion,'')
                 FROM devices
                 ORDER BY id;" 2>/dev/null |
        while IFS='|' read id uid busId syncId serial serialPowerUnit radioId enabled radioChannel radioAddress timeCreated timeModified swVersion; do
                uidj="$(json_escape_one "$uid")"
                serialj="$(json_escape_one "$serial")"
                serialPowerUnitj="$(json_escape_one "$serialPowerUnit")"
                timeCreatedj="$(json_escape_one "$timeCreated")"
                timeModifiedj="$(json_escape_one "$timeModified")"
                swVersionj="$(json_escape_one "$swVersion")"

                pub "tele/$TOPIC/DB/DEVICE/$uidj" "{\"Time\":\"$(iso_time)\",\"DbId\":$id,\"Uid\":\"$uidj\",\"BusId\":$busId,\"SyncId\":$syncId,\"Serial\":\"$serialj\",\"SerialPowerUnit\":\"$serialPowerUnitj\",\"RadioId\":$radioId,\"Enabled\":$enabled,\"RadioChannel\":$radioChannel,\"RadioAddress\":$radioAddress,\"TimeCreated\":\"$timeCreatedj\",\"TimeModified\":\"$timeModifiedj\",\"SwVersion\":\"$swVersionj\"}"
        done
}

publish_db_logs() {
        db_snapshot || return
        DB="/tmp/router-mqtt-chsd.sqlite"

        sqlite3 -separator '|' "$DB" \
                "SELECT d.uid,
                        l.id,
                        l.usageTime,
                        l.usageDuration,
                        l.powerConsumption,
                        l.waterConsumption,
                        ifnull(l.customId,0),
                        ifnull(l.tap_id,0)
                 FROM logs AS l
                 JOIN devices AS d ON d.id = l.device_id
                 ORDER BY l.id DESC
                 LIMIT 10;" 2>/dev/null |
        while IFS='|' read uid log_id usage_time usage_duration power water custom_id tap_id; do
                uidj="$(json_escape_one "$uid")"

                pub "tele/$TOPIC/DB/LOG/$log_id" "{\"Time\":\"$(iso_time)\",\"DeviceUid\":\"$uidj\",\"LogId\":$log_id,\"UsageTime\":$usage_time,\"UsageDuration\":$usage_duration,\"PowerConsumption\":$power,\"WaterConsumption\":$water,\"CustomId\":$custom_id,\"TapId\":$tap_id}"
        done
}

publish_db_timers() {
        db_snapshot || return
        DB="/tmp/router-mqtt-chsd.sqlite"

        sqlite3 -separator '|' "$DB" \
                "SELECT t.id,
                        ifnull(d.uid,''),
                        ifnull(t.enabled,0),
                        ifnull(t.status,0),
                        ifnull(t.type,0),
                        ifnull(t.weekdays,0),
                        ifnull(t.start,''),
                        ifnull(t.stop,''),
                        ifnull(t.setpoint,0)
                 FROM timers AS t
                 LEFT JOIN devices AS d ON d.id = t.device_id
                 ORDER BY t.id;" 2>/dev/null |
        while IFS='|' read timer_id uid enabled status type weekdays start stop setpoint; do
                uidj="$(json_escape_one "$uid")"
                startj="$(json_escape_one "$start")"
                stopj="$(json_escape_one "$stop")"

                pub "tele/$TOPIC/DB/TIMER/$timer_id" "{\"Time\":\"$(iso_time)\",\"TimerId\":$timer_id,\"DeviceUid\":\"$uidj\",\"Enabled\":$enabled,\"Status\":$status,\"Type\":$type,\"Weekdays\":$weekdays,\"Start\":\"$startj\",\"Stop\":\"$stopj\",\"Setpoint\":$setpoint}"
        done
}

num() {
        echo "$1" | sed 's/[^0-9.-]//g'
}

save() {
        echo "$2" > "$STATE/$1"
}

readv() {
        cat "$STATE/$1" 2>/dev/null || echo 0
}

json_escape() {
        sed 's/\\/\\\\/g; s/"/\\"/g'
}

service_alive() {
        pidof "$1" >/dev/null 2>&1 && echo 1 || echo 0
}

get_hostname() {
        cat /proc/sys/kernel/hostname 2>/dev/null
}

get_ip() {
        ifconfig br-lan 2>/dev/null | awk '/inet addr:/ { sub("addr:","",$2); print $2 }'
}

get_mem() {
        awk -v k="$1" '$1 == k ":" { print $2 }' /proc/meminfo 2>/dev/null
}

publish_state() {
        HOST="$(get_hostname)"
        IP="$(get_ip)"
        UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
        LOAD="$(cat /proc/loadavg 2>/dev/null | awk '{print $1","$2","$3}')"

        MEM_TOTAL="$(get_mem MemTotal)"
        MEM_FREE="$(get_mem MemFree)"
        MEM_AVAIL="$(get_mem MemAvailable)"
        [ -n "$MEM_AVAIL" ] || MEM_AVAIL="$MEM_FREE"

        if [ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" -gt 0 ] 2>/dev/null; then
                MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
                MEM_USED_PCT=$((MEM_USED * 100 / MEM_TOTAL))
        else
                MEM_USED=0
                MEM_USED_PCT=0
        fi

        DF="$(df -P /overlay 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $2","$3","$4","$5}')"

        LIGHTTPD="$(service_alive lighttpd)"
        CHSD="$(service_alive chsd)"
        COLLECTD="$(service_alive collectd)"

        IOW0=0
        IOW1=0
        [ -e /dev/usb/iowarrior0 ] && IOW0=1
        [ -e /dev/usb/iowarrior1 ] && IOW1=1

        pub "$BASE_TELE/STATE" "{\"Time\":$(date +%s),\"Hostname\":\"$HOST\",\"IPAddress\":\"$IP\",\"Uptime\":$UPTIME,\"Load\":\"$LOAD\",\"Memory\":{\"Total\":$MEM_TOTAL,\"Free\":$MEM_FREE,\"Available\":$MEM_AVAIL,\"UsedPercent\":$MEM_USED_PCT},\"StorageOverlay\":\"$DF\",\"Services\":{\"chsd\":$CHSD,\"lighttpd\":$LIGHTTPD,\"collectd\":$COLLECTD},\"IOWarrior\":{\"0\":$IOW0,\"1\":$IOW1}}"
}

publish_chsd() {
        TX_TOTAL="$(readv tx_total)"
        TX_PERCENT="$(readv tx_percent)"
        TX_R="$(readv tx_r)"
        TX_E="$(readv tx_e)"

        RX_TOTAL="$(readv rx_total)"
        RX_PERCENT="$(readv rx_percent)"
        RX_S="$(readv rx_s)"
        RX_S2="$(readv rx_s2)"
        RX_M="$(readv rx_m)"
        RX_M2="$(readv rx_m2)"
        RX_L="$(readv rx_l)"
        RX_L2="$(readv rx_l2)"
        RX_I="$(readv rx_i)"
        RX_O="$(readv rx_o)"

        LAST_RSSI="$(readv last_rssi)"
        LAST_LQI="$(readv last_lqi)"
        LAST_BUS="$(readv last_bus)"
        LAST_DEVICE="$(readv last_device)"

        pub "$BASE_TELE/CHSD" "{\"Time\":$(date +%s),\"TX\":{\"Total\":$TX_TOTAL,\"Percent\":$TX_PERCENT,\"R\":$TX_R,\"E\":$TX_E},\"RX\":{\"Total\":$RX_TOTAL,\"Percent\":$RX_PERCENT,\"S\":$RX_S,\"S2\":$RX_S2,\"M\":$RX_M,\"M2\":$RX_M2,\"L\":$RX_L,\"L2\":$RX_L2,\"I\":$RX_I,\"O\":$RX_O},\"RF\":{\"LastRSSI\":$LAST_RSSI,\"LastLQI\":$LAST_LQI,\"LastBus\":\"$LAST_BUS\",\"LastDevice\":\"$LAST_DEVICE\"}}"
}

publish_clage() {
        curl -ks -o /tmp/router-mqtt-clage.json -w "%{http_code}" "https://admin:geheim@127.0.0.1/devices" > /tmp/router-mqtt-code

        CODE="$(cat /tmp/router-mqtt-code 2>/dev/null)"
        if [ "$CODE" = "200" ]; then
                pub "$BASE_TELE/CLAGE" "$(cat /tmp/router-mqtt-clage.json)"
                pub "$BASE_TELE/SENSOR" "{\"Time\":$(date +%s),\"CLAGE\":{\"ApiOk\":1},\"CHSD\":{\"TxTotal\":$(readv tx_total),\"RxTotal\":$(readv rx_total),\"LastRSSI\":$(readv last_rssi),\"LastLQI\":$(readv last_lqi)}}"
        else
                pub "$BASE_TELE/SENSOR" "{\"Time\":$(date +%s),\"CLAGE\":{\"ApiOk\":0,\"HttpCode\":$CODE},\"CHSD\":{\"TxTotal\":$(readv tx_total),\"RxTotal\":$(readv rx_total)}}"
        fi
}

publish_all() {
        publish_state
        publish_chsd
        publish_clage_devices
        publish_db_summary
}

publish_clage_devices() {
        curl -ks -o /tmp/router-mqtt-devices.json -w "%{http_code}" "https://admin:geheim@127.0.0.1/devices" > /tmp/router-mqtt-devices-code

        CODE="$(cat /tmp/router-mqtt-devices-code 2>/dev/null)"
        if [ "$CODE" != "200" ]; then
                pub "tele/$TOPIC/CLAGE" "{\"Time\":\"$(iso_time)\",\"ApiOk\":0,\"HttpCode\":$CODE}"
                return
        fi

        # JSON complet brut, utile pour Jeedom/Node-RED/Home Assistant
        pub "tele/$TOPIC/CLAGE" "$(cat /tmp/router-mqtt-devices.json)"

        # Si jsonfilter est dispo, on publie aussi un résumé par appareil
        if command -v jsonfilter >/dev/null 2>&1; then
                COUNT="$(jsonfilter -i /tmp/router-mqtt-devices.json -e '@.devices[*].id' 2>/dev/null | wc -l)"

                i=0
                while [ "$i" -lt "$COUNT" ]; do
                        ID="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].id" 2>/dev/null)"
                        NAME="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].name" 2>/dev/null)"
                        BUSID="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].busId" 2>/dev/null)"
                        RSSI="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].rssi" 2>/dev/null)"
                        LQI="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].lqi" 2>/dev/null)"
                        CONNECTED="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].connected" 2>/dev/null)"
                        SETPOINT="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].info.setpoint" 2>/dev/null)"
                        ERROR="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].info.error" 2>/dev/null)"
                        ACTIVITY="$(jsonfilter -i /tmp/router-mqtt-devices.json -e "@.devices[$i].info.activity" 2>/dev/null)"

                        [ -n "$ID" ] || {
                                i=$((i + 1))
                                continue
                        }

                        [ -n "$RSSI" ] || RSSI=0
                        [ -n "$LQI" ] || LQI=0
                        [ -n "$BUSID" ] || BUSID=0
                        [ -n "$SETPOINT" ] || SETPOINT=0
                        [ -n "$ERROR" ] || ERROR=0
                        [ -n "$ACTIVITY" ] || ACTIVITY=0

                        case "$CONNECTED" in
                                true|1) CONNECTED=1 ;;
                                *) CONNECTED=0 ;;
                        esac

                        NAME_ESC="$(json_escape_one "$NAME")"

                        pub "tele/$TOPIC/DEVICE/$ID/STATE" "{\"Time\":\"$(iso_time)\",\"Id\":\"$ID\",\"Name\":\"$NAME_ESC\",\"BusId\":$BUSID,\"Connected\":$CONNECTED,\"RSSI\":$RSSI,\"LQI\":$LQI,\"Setpoint\":$SETPOINT,\"Error\":$ERROR,\"Activity\":$ACTIVITY}"

                        i=$((i + 1))
                done
        fi
}

parse_chsd_log_line() {
        line="$1"

        echo "$line" | grep 'chsd' >/dev/null 2>&1 || return

        if echo "$line" | grep 'TX total=' >/dev/null 2>&1; then
                echo "$line" | sed -n 's/.*TX total=[ ]*\([0-9]*\).*([ ]*\([0-9.]*\)%).*R=[ ]*\([0-9]*\), E=[ ]*\([0-9]*\).*/\1 \2 \3 \4/p' > /tmp/router-mqtt-tx
                read a b c d < /tmp/router-mqtt-tx
                [ -n "$a" ] && save tx_total "$a"
                [ -n "$b" ] && save tx_percent "$b"
                [ -n "$c" ] && save tx_r "$c"
                [ -n "$d" ] && save tx_e "$d"
                publish_chsd
                return
        fi

        if echo "$line" | grep 'RX total=' >/dev/null 2>&1; then
                echo "$line" | sed -n 's/.*RX total=[ ]*\([0-9]*\).*([ ]*\([0-9.]*\)%).*S=[ ]*\([0-9]*\) ([ ]*\([0-9]*\)), M=[ ]*\([0-9]*\) ([ ]*\([0-9]*\)), L=[ ]*\([0-9]*\) ([ ]*\([0-9]*\)), I=[ ]*\([0-9]*\), O=[ ]*\([0-9]*\).*/\1 \2 \3 \4 \5 \6 \7 \8 \9/p' > /tmp/router-mqtt-rx
                read a b c d e f g h i < /tmp/router-mqtt-rx
                [ -n "$a" ] && save rx_total "$a"
                [ -n "$b" ] && save rx_percent "$b"
                [ -n "$c" ] && save rx_s "$c"
                [ -n "$d" ] && save rx_s2 "$d"
                [ -n "$e" ] && save rx_m "$e"
                [ -n "$f" ] && save rx_m2 "$f"
                [ -n "$g" ] && save rx_l "$g"
                [ -n "$h" ] && save rx_l2 "$h"
                [ -n "$i" ] && save rx_i "$i"

                o="$(echo "$line" | sed -n 's/.* O=[ ]*\([0-9]*\).*/\1/p')"
                [ -n "$o" ] && save rx_o "$o"

                publish_chsd
                return
        fi

        if echo "$line" | grep 'RSSI' >/dev/null 2>&1; then
                rssi="$(echo "$line" | sed -n 's/.*RSSI[ ]*\(-*[0-9]*\)[ ]*dBm.*/\1/p')"
                lqi="$(echo "$line" | sed -n 's/.*LQI[ ]*\([0-9]*\).*/\1/p')"
                dev="$(echo "$line" | sed -n 's/.*RX (# *[0-9]*) \([^ ]*\) < \([^:]*\):.*/\1/p')"
                bus="$(echo "$line" | sed -n 's/.*RX (# *[0-9]*) \([^ ]*\) < \([^:]*\):.*/\2/p')"

                [ -n "$rssi" ] && save last_rssi "$rssi"
                [ -n "$lqi" ] && save last_lqi "$lqi"
                [ -n "$dev" ] && save last_device "$dev"
                [ -n "$bus" ] && save last_bus "$bus"
                return
        fi
}

log_loop() {
        logread -f | while read line; do
                parse_chsd_log_line "$line"
        done
}

tele_loop() {
        pubr "$BASE_TELE/LWT" "Online"
        while :; do
                publish_all
                sleep "$INTERVAL"
        done
}

handle_command() {
        fulltopic="$1"
        payload="$2"

        cmd="${fulltopic#$BASE_CMND/}"
        cmd="$(echo "$cmd" | tr 'a-z' 'A-Z')"

        case "$cmd" in
                STATUS)
                        case "$payload" in
                                ""|0) publish_status_0 ;;
                                1) publish_status_1 ;;
                                2) publish_status_2 ;;
                                5) publish_status_5 ;;
                                8) publish_status_8 ;;
                                10) publish_status_10 ;;
                                *) publish_status_0 ;;
                        esac
                        pub "$BASE_STAT/RESULT" "{\"STATUS$payload\":\"DONE\"}"
                        ;;

                TELEPERIOD)
                        if echo "$payload" | grep -q '^[0-9][0-9]*$'; then
                                if [ "$payload" -ge 10 ] 2>/dev/null && [ "$payload" -le 3600 ] 2>/dev/null; then
                                        INTERVAL="$payload"
                                        pub "$BASE_STAT/RESULT" "{\"TelePeriod\":$INTERVAL}"
                                else
                                        pub "$BASE_STAT/RESULT" "{\"TelePeriod\":\"Invalid\"}"
                                fi
                        else
                                pub "$BASE_STAT/RESULT" "{\"TelePeriod\":$INTERVAL}"
                        fi
                        ;;

                POWER|POWER1)
                        pub "$BASE_STAT/RESULT" "{\"POWER\":\"OFF\",\"Warning\":\"No relay on this device\"}"
                        ;;

                MODULE)
                        pub "$BASE_STAT/RESULT" "{\"Module\":{\"0\":\"CLAGE CHS OpenWrt\"}}"
                        ;;

                FRIENDLYNAME|FRIENDLYNAME1)
                        pub "$BASE_STAT/RESULT" "{\"FriendlyName1\":\"$FRIENDLY_NAME\"}"
                        ;;

                TOPIC)
                        pub "$BASE_STAT/RESULT" "{\"Topic\":\"$TOPIC\"}"
                        ;;

                FULLTOPIC)
                        pub "$BASE_STAT/RESULT" "{\"FullTopic\":\"%prefix%/%topic%/\"}"
                        ;;

                MQTTHOST)
                        pub "$BASE_STAT/RESULT" "{\"MqttHost\":\"$BROKER\"}"
                        ;;

                DISCOVERY|SETOPTION19)
                        publish_tasmota_discovery
                        publish_tasmota_info
                        publish_commands_discovery
                        pub "$BASE_STAT/RESULT" "{\"SetOption19\":\"OFF\",\"Discovery\":\"Published\"}"
                        ;;

                DB)
                        publish_db_summary
                        publish_db_devices
                        publish_db_logs
                        publish_db_timers
                        pub "$BASE_STAT/RESULT" "{\"DB\":\"DONE\"}"
                        ;;

                DBSCHEMA)
                        db_snapshot && sqlite3 /tmp/router-mqtt-chsd.sqlite ".tables" > /tmp/router-mqtt-db-tables 2>/dev/null
                        tables="$(cat /tmp/router-mqtt-db-tables 2>/dev/null | tr '\n' ' ' | json_escape_one)"
                        pub "$BASE_STAT/RESULT" "{\"DBSCHEMA\":\"$tables\"}"
                        ;;

                POLL)
                        publish_all
                        pub "$BASE_STAT/RESULT" "{\"POLL\":\"DONE\"}"
                        ;;

                RESTART_CHSD)
                        /etc/init.d/chsd restart >/dev/null 2>&1
                        pub "$BASE_STAT/RESULT" "{\"RESTART_CHSD\":\"DONE\"}"
                        ;;

                RESTART_HTTPD|RESTART_LIGHTTPD)
                        /etc/init.d/lighttpd restart >/dev/null 2>&1
                        pub "$BASE_STAT/RESULT" "{\"RESTART_LIGHTTPD\":\"DONE\"}"
                        ;;

                RESTART)
                        # Tasmota fait un restart device avec Restart 1.
                        # Ici je le rends volontairement prudent : Restart 1 redémarre le service MQTT, pas le routeur entier.
                        if [ "$payload" = "1" ]; then
                                pub "$BASE_STAT/RESULT" "{\"Restart\":\"Restarting router-mqtt\"}"
                                sleep 1
                                /etc/init.d/router-mqtt restart >/dev/null 2>&1
                        else
                                pub "$BASE_STAT/RESULT" "{\"Restart\":\"Payload 1 required\"}"
                        fi
                        ;;

                REBOOT)
                        if [ "$payload" = "1" ] || [ "$payload" = "ON" ] || [ "$payload" = "YES" ]; then
                                pub "$BASE_STAT/RESULT" "{\"REBOOT\":\"STARTING\"}"
                                sleep 2
                                reboot
                        else
                                pub "$BASE_STAT/RESULT" "{\"REBOOT\":\"REFUSED\",\"Hint\":\"payload 1 required\"}"
                        fi
                        ;;

                *)
                        pub "$BASE_STAT/RESULT" "{\"Command\":\"$cmd\",\"Error\":\"Unknown command\"}"
                        ;;
        esac
}

cmnd_loop() {
        [ -x "$MQTT_SUB" ] || return

        $MQTT_SUB -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -v -t "$BASE_CMND/#" | while read topic payload; do
                handle_command "$topic" "$payload"
        done
}

stop_old() {
        kill "$(cat /tmp/router-mqtt.log.pid 2>/dev/null)" 2>/dev/null
        kill "$(cat /tmp/router-mqtt.tele.pid 2>/dev/null)" 2>/dev/null
        kill "$(cat /tmp/router-mqtt.cmnd.pid 2>/dev/null)" 2>/dev/null
}

case "$1" in
        stop)
                pubr "$BASE_TELE/LWT" "Offline"
                stop_old
                exit 0
                ;;
esac

stop_old
publish_tasmota_discovery
publish_tasmota_info
publish_commands_discovery

log_loop &
echo $! > /tmp/router-mqtt.log.pid

tele_loop &
echo $! > /tmp/router-mqtt.tele.pid

cmnd_loop &
echo $! > /tmp/router-mqtt.cmnd.pid

wait
