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


addon_id="$1"
dyno_client_id="$2"
api_base_url="$3"

seconds_per_75_mins=4500

function _extend_private_app_tunnel() {
    http_response_status=$(curl --request POST \
        "${api_base_url}/heroku/resources/${addon_id}/private-app-tunnels" \
        --data-raw "{\"clientId\":\"${dyno_client_id}\",\"autoDestroyDelaySeconds\":${seconds_per_75_mins}}" \
        --header "Authorization: Bearer ${CLIENT_APP_JWT}" \
        --header "Content-Type: application/json" \
        --write-out "%{http_code}" \
        --silent \
        --output "/dev/null")

    curl_exit_code=$?
    if [[ "$curl_exit_code" -ne 0 ]]
    then
        # Generally means a networking error of some sort occurred
        return $curl_exit_code
    elif [[ "$http_response_status" -ge 500 ]]
    then
        # Response status indicates a server-side error (HTTP 5xx)
        return 99
    else
        return 0
    fi
}

function _destroy_private_app_tunnel() {
    curl --request DELETE \
        "${api_base_url}/heroku/resources/${addon_id}/private-app-tunnels/${dyno_client_id}" \
        --header "Authorization: Bearer ${CLIENT_APP_JWT}" \
        --header "Content-Type: application/json" &>/dev/null

    exit $?
}

# Register the function that will clean up the private app tunnel when the dyno/server shuts down
trap _destroy_private_app_tunnel EXIT

# Keep the private app tunnel alive for as long as the dyno/server remains online. Extend it by 75
# minutes at a time. If the loop is interrupted and the EXIT handler doesn't run (i.e. the
# dyno/server did not shut down cleanly), the private app tunnel will be auto-destroyed within 75
# minutes at most.
sleep 1h 5m

while true
do
    _extend_private_app_tunnel

    tunnel_exit_code=$?
    if [[ "$tunnel_exit_code" -eq 0 ]]
    then
        # Wait until there is about 10 minutes left of the auto-destroy delay so that, if there is a
        # network or server-side error on the next attempt to extend the private app tunnel, there
        # will be time to try again before the private app tunnel is auto-destroyed
        sleep 1h 5m
    else
        # The tunnel extension request failed, so wait a few minutes and then try again
        sleep 3m
    fi
done
