#!/bin/bash
# Wrapper for Thunderbird to ensure it runs with the correct profile and settings.

# The one-time-setup script creates this specific profile. We want to ensure
# all launches of Thunderbird use it, rather than creating a new random one.
PROFILE_DIR="/home/user/.thunderbird/bytebotprofile.default"

# Ensure the profile directory exists
mkdir -p "$PROFILE_DIR"

# Launch Thunderbird with the specified profile.
# The "$@" passes along any arguments that were sent to the wrapper.
exec /usr/lib/thunderbird/thunderbird -profile "$PROFILE_DIR" "$@"
