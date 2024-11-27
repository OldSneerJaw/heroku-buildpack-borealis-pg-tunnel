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


conn_info_env_var_pattern='^(.+)_TUNNEL_BPG_CONN_INFO$'
legacy_conn_info_env_var_pattern='^(.+)_SSH_TUNNEL_BPG_CONNECTION_INFO$'
pg_url_pattern='^postgres(ql)?://[^@]+@([^:]+):([[:digit:]]+)/.+$'
buildpack_dir="${HOME}/.borealis-pg"
ssh_config_dir="${HOME}/.ssh"
default_autossh_dir="${buildpack_dir}/autossh"
processed_entries=()
seconds_per_75_mins=4500

if [[ -d "$default_autossh_dir" ]]
then
    autossh_dir="$default_autossh_dir"
else
    autossh_dir="/usr/bin"
fi

function normalizeConnItemValue() {
    local conn_item_value="$1"

    echo "${conn_item_value//\\n/$'\n'}"
}

all_env_vars=$(awk 'BEGIN { for (name in ENVIRON) { print name } }')
for env_var in $all_env_vars
do
    # Reset all tunnel connection variables
    postgres_internal_port='5432'
    ssh_port='22'
    addon_id=''
    api_base_url=''
    client_app_jwt=''
    postgres_writer_host=''
    postgres_reader_host=''
    ssh_host=''
    ssh_public_host_key=''
    ssh_username=''
    ssh_user_private_key=''
    tunnel_writer_url_host=''
    tunnel_writer_url_port=''
    tunnel_reader_url_host=''
    tunnel_reader_url_port=''

    if [[ "$env_var" =~ $conn_info_env_var_pattern ]] || [[ "$env_var" =~ $legacy_conn_info_env_var_pattern ]]
    then
        addon_env_var_prefix="${BASH_REMATCH[1]}"

        # There should be a corresponding "*_URL" connection string environment variable
        addon_db_conn_str=$(printenv "${addon_env_var_prefix}_URL" || echo '')
        if [[ "$addon_db_conn_str" =~ $pg_url_pattern ]]
        then
            # Retrieve the local host and port for the writer SSH tunnel from the "*_URL" env var
            # value
            tunnel_writer_url_host="${BASH_REMATCH[2]}"
            tunnel_writer_url_port="${BASH_REMATCH[3]}"

            # Retrieve the local host and port for the reader SSH tunnel from the "*_READONLY_URL"
            # env var value, if it exists
            addon_readonly_db_conn_str=$(printenv "${addon_env_var_prefix}_READONLY_URL" || echo '')
            if [[ "$addon_readonly_db_conn_str" =~ $pg_url_pattern ]]
            then
                tunnel_reader_url_host="${BASH_REMATCH[2]}"
                tunnel_reader_url_port="${BASH_REMATCH[3]}"
            fi

            # Retrieve the secure tunnel connection details from the tunnel connection info env var
            ssh_connection_info=$(printenv "$env_var")
            IFS=$'|' read -r -d '' -a conn_info_array <<< "$ssh_connection_info"
            for conn_item in "${conn_info_array[@]}"
            do
                if [[ "$conn_item" =~ ^ADDON_ID:=(.+)$ ]]
                then
                    addon_id=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^API_BASE_URL:=(.+)$ ]]
                then
                    api_base_url=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^CLIENT_APP_JWT:=(.+)$ ]]
                then
                    client_app_jwt=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^POSTGRES_WRITER_HOST:=(.+)$ ]]
                then
                    postgres_writer_host=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^POSTGRES_READER_HOST:=(.+)$ ]]
                then
                    postgres_reader_host=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^POSTGRES_PORT:=(.+)$ ]]
                then
                    postgres_internal_port=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^SSH_HOST:=(.+)$ ]]
                then
                    ssh_host=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^SSH_PORT:=(.+)$ ]]
                then
                    ssh_port=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^SSH_PUBLIC_HOST_KEY:=(.+)$ ]]
                then
                    ssh_public_host_key=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^SSH_USERNAME:=(.+)$ ]]
                then
                    ssh_username=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                elif [[ "$conn_item" =~ ^SSH_USER_PRIVATE_KEY:=(.+)$ ]]
                then
                    ssh_user_private_key=$(normalizeConnItemValue "${BASH_REMATCH[1]}")
                fi
            done

            # The same add-on can be attached to an app multiple times with different
            # config/environment variables, so only set up a secure tunnel if it hasn't already been
            # initialized in a previous iteration
            if [[ ! "${processed_entries[*]}" =~ $addon_db_conn_str ]]
            then
                processed_entries+=("$addon_db_conn_str")

                if [[ "$tunnel_writer_url_host" != "pg-tunnel.borealis-data.com" ]]
                then
                    # The add-on expects the client to register its IP address to connect rather
                    # than use SSH port forwarding
                    boot_id=$(echo -n "$(cat /proc/sys/kernel/random/boot_id)")
                    dyno_client_id="${DYNO}_${boot_id}"
                    curl --fail \
                        --request POST \
                        "${api_base_url}/heroku/resources/${addon_id}/private-app-tunnels" \
                        --data-raw "{\"clientId\":\"${dyno_client_id}\",\"autoDestroyDelaySeconds\":${seconds_per_75_mins}}" \
                        --header "Authorization: Bearer ${client_app_jwt}" \
                        --header "Content-Type: application/json" &>/dev/null || exit $?

                    # Start a process in the background that will wait for the server to shut down
                    # and then destroy the private app tunnel
                    CLIENT_APP_JWT="$client_app_jwt" "$buildpack_dir"/server-shutdown-wait.sh \
                        "$addon_id" \
                        "$dyno_client_id" \
                        "$api_base_url" &
                else
                    ssh_private_key_path="${ssh_config_dir}/borealis-pg_${ssh_username}_${ssh_host}.pem"

                    # Create the SSH configuration directory if it doesn't already exist
                    mkdir -p "$ssh_config_dir"
                    chmod 700 "$ssh_config_dir"

                    # The SSH private key file doesn't yet exist, so create and populate it
                    echo "$ssh_user_private_key" > "$ssh_private_key_path"
                    chmod 400 "$ssh_private_key_path"

                    # Add the SSH server's public host key to known_hosts for server authentication
                    echo "${ssh_host} ${ssh_public_host_key}" >> "${ssh_config_dir}/known_hosts"

                    # Set up the port forwarding argument(s)
                    writer_port_forward="${tunnel_writer_url_host}:${tunnel_writer_url_port}:${postgres_writer_host}:${postgres_internal_port}"
                    if [[ -n "$postgres_reader_host" ]] && [[ -n "$tunnel_reader_url_port" ]]
                    then
                        reader_port_forward="${tunnel_reader_url_host}:${tunnel_reader_url_port}:${postgres_reader_host}:${postgres_internal_port}"
                        port_forward_args=(-L "$writer_port_forward" -L "$reader_port_forward")
                    else
                        port_forward_args=(-L "$writer_port_forward")
                    fi

                    # Create the SSH tunnel
                    "$autossh_dir"/autossh \
                        -M 0 \
                        -f \
                        -N \
                        -o TCPKeepAlive=no \
                        -o ServerAliveCountMax=3 \
                        -o ServerAliveInterval=15 \
                        -o ExitOnForwardFailure=yes \
                        -p "$ssh_port" \
                        -i "$ssh_private_key_path" \
                        "${port_forward_args[@]}" \
                        "${ssh_username}@${ssh_host}" \
                        || exit $?
                fi
            fi
        fi
    fi
done
