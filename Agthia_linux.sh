#!/bin/bash

# Define the rsyslog configuration file
RSYSLOG_CONF="/etc/rsyslog.conf"

# Check if the file exists
if [ ! -f "$RSYSLOG_CONF" ]; then
    echo "Error: $RSYSLOG_CONF does not exist."
    exit 1
fi

# Add 'module(load="imfile")' below the MODULES section
if ! grep -q 'module(load="imfile")' "$RSYSLOG_CONF"; then
    awk '/^#################/ && getline && /^#### MODULES ####/ && getline && /^#################/ {
        print $0 "\nmodule(load=\"imfile\")";
        next
    }1' "$RSYSLOG_CONF" > /tmp/rsyslog_new.conf && mv /tmp/rsyslog_new.conf "$RSYSLOG_CONF"
    echo "Added module(load=\"imfile\") under the MODULES section."
else
    echo "module(load=\"imfile\") already exists."
fi

# Append '*.* @192.168.72.150:514' at the end of the file if not already present
if ! grep -q '*.* @192.168.72.150:514' "$RSYSLOG_CONF"; then
    echo '*.* @192.168.72.150:514' >> "$RSYSLOG_CONF"
    echo "Added *.* @192.168.72.150:514 at the end of the file."
else
    echo "*.* @192.168.72.150:514 already exists."
fi

# Restart the rsyslog service
echo "Restarting rsyslog service..."
service rsyslog restart

# Verify if the restart was successful
if [ $? -eq 0 ]; then
    echo "Rsyslog service restarted successfully."
else
    echo "Failed to restart rsyslog service."
    exit 1
fi
