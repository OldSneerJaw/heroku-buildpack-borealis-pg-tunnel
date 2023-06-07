#!/usr/bin/env bash


# MIT License

# Copyright (c) Boreal Information Systems Inc.

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


ADDON_ID="$1"
DYNO_CLIENT_ID="$2"
API_BASE_URL="$3"

SECONDS_PER_2_HOURS='7200'

function _destroy_private_app_tunnel() {
    curl \
        --request DELETE \
        "${API_BASE_URL}/heroku/resources/${ADDON_ID}/private-app-tunnels/${DYNO_CLIENT_ID}" \
        --header "Authorization: Bearer ${CLIENT_APP_JWT}" \
        --header "Content-Type: application/json" &>/dev/null

    exit $?
}

# Register the function that will clean up the private app tunnel when the dyno/server shuts down
trap _destroy_private_app_tunnel EXIT

# Keep the private app tunnel alive for as long as the dyno/server remains online. Extend it by 2
# hours at a time. If the loop is interrupted and the EXIT handler doesn't run (i.e. the dyno/server
# did not shut down cleanly), the private app tunnel will be auto-destroyed within 2 hours at most.
while true
do
    # Wait for a little under half of the auto-destroy delay so that, if there is a network error on
    # the first attempt to extend the private app tunnel, there will be time to try again before it
    # is auto-destroyed
    sleep 58m || exit

    curl \
        --request POST \
        "${API_BASE_URL}/heroku/resources/${ADDON_ID}/private-app-tunnels" \
        --data-raw "{\"clientId\":\"${DYNO_CLIENT_ID}\",\"autoDestroyDelaySeconds\":${SECONDS_PER_2_HOURS}}" \
        --header "Authorization: Bearer ${CLIENT_APP_JWT}" \
        --header "Content-Type: application/json" &>/dev/null
done
