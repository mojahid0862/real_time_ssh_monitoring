
# SSH Login Monitoring with Google Chat Alerts

This Bash script automates the monitoring of SSH login and logout events on your Linux server. It captures detailed information about each event, such as the IP address, authentication method, geo-location, and active session details, then sends real-time notifications to a Google Chat space.

## Features

- **Real-time SSH login monitoring**: Tracks successful SSH login attempts in real-time.
- **Geo-location enrichment**: Fetches country, region, and city data for each login attempt.
- **Active session tracking**: Monitors active SSH connections and tracks the number of sessions per IP.
- **Session duration**: Logs the duration of each SSH session upon logout.
- **Google Chat alerts**: Sends real-time login/logout notifications to a specified Google Chat space.
  
## Prerequisites

- Linux-based system with SSH access logs in `/var/log/auth.log`.
- A Google Chat webhook URL to receive notifications (replace `YOUR_GOOGLECHAT_API_KEY` with your actual API key).
- `curl` and `jq` must be installed for making HTTP requests and parsing JSON data.
- `lsof` to check connections per IP.

## Installation

1. Clone this repository to your server.

   ```bash
   git git@github.com:mojahid0862/real_time_ssh_monitoring.git
   cd real_time_ssh_monitoring
   ```

2. Make the script executable.

   ```bash
   chmod +x ssh_connection.sh
   ```

3. Configure the **Google Chat Webhook URL**:

   Replace the placeholder `YOUR_GOOGLECHAT_API_KEY` in the script with your actual Google Chat Webhook URL.

4. Run the script as a background process to monitor SSH logins and logouts.

   ```bash
   nohup ./ssh_connection.sh &
   ```

## How It Works

- The script continuously monitors `/var/log/auth.log` for SSH login and logout events using `tail -f`.
- For each **successful login**, it collects:
  - IP address
  - Authentication method (password, publickey, or keyboard-interactive)
  - Geo-location data (country, region, city)
  - Current active SSH sessions
- For **logout events**, it logs the session duration (in hours, minutes, and seconds) and updates the active sessions count.
- All login and logout events trigger a message to your specified Google Chat space with detailed information.

### Example Notification (Login):
```json
{
  "text": "New SSH login detected:\n\nTime: 2024-12-01 12:30:45\nIP: 192.168.1.100\nAuth Method: password\nCountry: United States\nRegion: California\nCity: Los Angeles\n\nActive SSH connections: 5\nConnections for IP=192.168.1.100: 2\nConnections for IP=192.168.1.101: 3"
}
```

### Example Notification (Logout):
```json
{
  "text": "SSH logout detected:\n\nTime: 2024-12-01 12:50:30\nIP: 192.168.1.100\nAuth Method: password\nCountry: United States\nRegion: California\nCity: Los Angeles\nDuration: 00:19:45\n\nActive SSH connections: 4\nConnections for IP=192.168.1.100: 1\nConnections for IP=192.168.1.101: 3"
}
```

## Customization

- **Webhook URL**: Change the `WEBHOOK_URL` in the script to point to your own Google Chat webhook.
- **Log Files**: The script writes SSH login and logout attempts to two log files:
  - `/root/auth/ssh_connection_log.txt`: Stores login/logout events.
  - `/root/auth/debug_log.txt`: Stores detailed logs for debugging.

## Troubleshooting

- If you encounter issues retrieving geo-location data, ensure the server has internet access and `curl` is installed.
- Ensure the script has the necessary permissions to read `/var/log/auth.log` and write to the log files.


```

### Key Points:
- **Simple Setup**: Instructions are clear and easy to follow for setting up the script.
- **What it Does**: The features section gives a concise overview of the script’s capabilities.
- **Customization**: Allows users to easily configure the Google Chat webhook URL and manage logging.
- **Real-Time Monitoring**: Focuses on the real-time nature of the alerts and how the system works.

