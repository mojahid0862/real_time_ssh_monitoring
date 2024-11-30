#!/bin/bash

# Log file to save SSH login attempts
LOG_FILE="/root/auth/ssh_connection_log.txt"
DEBUG_LOG="/root/auth/debug_log.txt"

# Google Chat Webhook URL (your provided URL)
WEBHOOK_URL="YOOUR_GOOGLECHAT_API_KEY"

# Ensure the log files exist
touch "$LOG_FILE"
touch "$DEBUG_LOG"

# Declare an associative array to track active sessions by IP
declare -A active_sessions
declare -A session_start_times
declare -A session_active
declare -A ip_connection_count  # New array to track how many connections each IP has

# Function to get the number of active SSH connections
get_active_connections() {
    # Count the number of active SSH user sessions based on the sshd processes
    active_connections=$(ps aux | grep -E '[s]shd:.*@pts' | wc -l)
    
    # Alternatively, use `ss` to count only established SSH connections
    # active_connections=$(ss -tuln | grep ':22' | grep 'ESTABLISHED' | wc -l)
    
    echo "$active_connections"
}

# Function to get the number of connections per IP using lsof
get_connections_per_ip() {
    local ip="$1"
    # Count how many connections each IP has using lsof on port 22
    connections_per_ip=$(lsof -i :22 | grep "$ip" | wc -l)
    echo "$connections_per_ip"
}

# Function to get the connections per IP in the format "Connections for IP=IP_ADDRESS: COUNT"
get_connections_report() {
    local connections_report=""
    for ip in "${!ip_connection_count[@]}"; do
        # Only include the IP if the connection count is greater than 0
        if [[ ${ip_connection_count[$ip]} -gt 0 ]]; then
            connections_report+="Connections for IP=$ip: ${ip_connection_count[$ip]}\n"
        fi
    done
    echo -e "$connections_report"
}

# Continuous monitoring of the auth.log file
tail -f /var/log/auth.log | while read -r line
do
    # Debugging: Print the line being processed
    echo "Processing line: $line" >> "$DEBUG_LOG"

    # Filter out lines that contain successful SSH login attempts
    if [[ "$line" =~ sshd.*Accepted.*from ]]; then
        # Capture the date and time of the login
        LOGIN_TIME=$(date "+%Y-%m-%d %H:%M:%S")

        # Extract the IP address from the log entry
        IP=$(echo "$line" | grep -oP 'from \K[\d\.]+')

        # Attempt to extract the authentication method (if mentioned)
        if [[ "$line" =~ password ]]; then
            AUTH_METHOD="password"
        elif [[ "$line" =~ publickey ]]; then
            AUTH_METHOD="publickey"
        elif [[ "$line" =~ keyboard-interactive ]]; then
            AUTH_METHOD="keyboard-interactive"
        else
            AUTH_METHOD="unknown"
        fi

        # Debugging: Print extracted details
        echo "Captured IP: $IP | Auth Method: $AUTH_METHOD" >> "$DEBUG_LOG"

        # If both IP and Auth Method are found
        if [[ -n "$IP" && -n "$AUTH_METHOD" ]]; then
            # Get geo-location data using the IP address
            geo_data=$(curl -s "http://ip-api.com/json/$IP")
            
            # Check if the geo-data request was successful
            if [[ $? -ne 0 ]]; then
                echo "Error retrieving geo-data for IP: $IP" >> "$DEBUG_LOG"
                continue
            fi

            # Extract country, region, and city information from the geo_data JSON response
            COUNTRY=$(echo "$geo_data" | jq -r '.country')
            REGION_NAME=$(echo "$geo_data" | jq -r '.regionName')
            CITY=$(echo "$geo_data" | jq -r '.city')

            # Prepare the log entry for the login attempt
            LOG_ENTRY="Time: $LOGIN_TIME | IP: $IP | Auth Method: $AUTH_METHOD | Country: $COUNTRY | Region: $REGION_NAME | City: $CITY | Status: Login"

            # Debugging: Print the log entry to the debug file
            echo "Log Entry (Login): $LOG_ENTRY" >> "$DEBUG_LOG"

            # Append the log entry to the log file
            echo "$LOG_ENTRY" >> "$LOG_FILE"

            # Track the session start time for the connection (we'll use this to calculate the duration later)
            SESSION_START_TIME=$(date +%s)  # Store in seconds since epoch

            # Store the session in the active sessions array
            active_sessions["$IP"]=$SESSION_START_TIME
            session_start_times["$IP"]=$SESSION_START_TIME
            session_active["$IP"]=1  # Mark the session as active

            # Get active SSH connections count at the time of login
            ACTIVE_SESSIONS=$(get_active_connections)

            # Update the connection count for this IP
            ip_connection_count["$IP"]=$((ip_connection_count["$IP"] + 1))

            # Get the number of connections for this IP using lsof
            IP_CONNECTIONS=$(get_connections_per_ip "$IP")

            # Get the full connections report for all IPs
            CONNECTIONS_REPORT=$(get_connections_report)

            # Send message to Google Chat with the login details, active session count, and per-IP connection count
            LOGIN_CHAT_MESSAGE=$(cat <<EOF
{
    "text": "New SSH login detected:\n\nTime: $LOGIN_TIME\nIP: $IP\nAuth Method: $AUTH_METHOD\nCountry: $COUNTRY\nRegion: $REGION_NAME\nCity: $CITY\n\nActive SSH connections: $ACTIVE_SESSIONS\n$CONNECTIONS_REPORT"
}
EOF
            )

            # Send the message to Google Chat using the webhook
            curl -X POST -H "Content-Type: application/json" -d "$LOGIN_CHAT_MESSAGE" "$WEBHOOK_URL"
        else
            # Log a message if no IP or auth method is found
            echo "Failed to capture login details from the log entry: $line" >> "$DEBUG_LOG"
        fi
    fi

    # Check for logout event (detect disconnections from active sessions)
    if [[ "$line" =~ sshd.*Received\ disconnect.*from ]]; then
        # Extract IP from the log line
        IP=$(echo "$line" | grep -oP 'from \K[\d\.]+')

        # If we have a valid session for the given IP
        if [[ -n "${session_active[$IP]}" && "${session_active[$IP]}" -eq 1 ]]; then
            LOGOUT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
            SESSION_END_TIME=$(date +%s)  # Store in seconds since epoch
            SESSION_DURATION=$((SESSION_END_TIME - session_start_times["$IP"]))  # Calculate session duration in seconds

            # Convert duration to a human-readable format (HH:MM:SS)
            HOURS=$((SESSION_DURATION / 3600))
            MINUTES=$(((SESSION_DURATION % 3600) / 60))
            SECONDS=$((SESSION_DURATION % 60))

            # Prepare the log entry for the logout event
            LOG_ENTRY="Time: $LOGOUT_TIME | IP: $IP | Auth Method: ${AUTH_METHOD} | Country: $COUNTRY | Region: $REGION_NAME | City: $CITY | Status: Logout | Duration: ${HOURS}:${MINUTES}:${SECONDS}"

            # Debugging: Print the log entry to the debug file
            echo "Log Entry (Logout): $LOG_ENTRY" >> "$DEBUG_LOG"

            # Append the log entry to the log file
            echo "$LOG_ENTRY" >> "$LOG_FILE"

            # Update active sessions count after logout
            session_active["$IP"]=0  # Mark session as inactive

            # Decrease the count for this IP in the ip_connection_count array
            ip_connection_count["$IP"]=$((ip_connection_count["$IP"] - 1))

            # Get active SSH connections count at the time of logout
            ACTIVE_SESSIONS=$(get_active_connections)

            # Get the number of connections for this IP using lsof
            IP_CONNECTIONS=$(get_connections_per_ip "$IP")

            # Get the full connections report for all IPs
            CONNECTIONS_REPORT=$(get_connections_report)

            # Send message to Google Chat with the logout details, active session count, and per-IP connection count
            LOGOUT_CHAT_MESSAGE=$(cat <<EOF
{
    "text": "SSH logout detected:\n\nTime: $LOGOUT_TIME\nIP: $IP\nAuth Method: $AUTH_METHOD\nCountry: $COUNTRY\nRegion: $REGION_NAME\nCity: $CITY\nDuration: ${HOURS}:${MINUTES}:${SECONDS}\n\nActive SSH connections: $ACTIVE_SESSIONS\n$CONNECTIONS_REPORT"
}
EOF
            )

            # Send the message to Google Chat using the webhook
            curl -X POST -H "Content-Type: application/json" -d "$LOGOUT_CHAT_MESSAGE" "$WEBHOOK_URL"
        fi
    fi
done
