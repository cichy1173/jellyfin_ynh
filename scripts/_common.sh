#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

debian=$(lsb_release --codename --short)
pkg_version="10.8.13-1"
version=$(echo "$pkg_version" | cut -d '-' -f 1)

ffmpeg_pkg_version="5.1.4-3"
ldap_pkg_version="17.0.0.0"

discovery_service_port=1900
discovery_client_port=7359

# Those directories are handled by the deb package
data_path="/var/lib/$app"
config_path="/etc/$app"
log_path="/var/log/$app"
cache_path="/var/cache/$app"


#=================================================
# PERSONAL HELPERS
#=================================================

ffmpeg_deps=(
	libass9
	libbluray2
	libc6
	libdrm2
	libfontconfig1
	libfreetype6
	libfribidi0
	libgcc1
	libgmp10
	libgnutls30
	libllvm13
	libmp3lame0
	libopus0
	libstdc++6
	libtheora0
	libvdpau1
	libvorbis0a
	libvorbisenc2
	libwebp6
	libwebpmux3
	libx11-6
	libxcb-randr0
	libzvbi0
	zlib1g
)

case "$debian" in
	buster) ffmpeg_deps+=( libvpx5 libx264-155 libx265-165 ) ;;
	bullseye) ffmpeg_deps+=( libvpx6 libx264-160 libx265-192 ) ;;
	*) echo "Unknown release: $debian" >&2; exit 1 ;;
esac
case "$YNH_ARCH" in
	arm64) : ;;
	armhf) : ;;
	*) ffmpeg_deps+=( libdrm-intel1 libopencl1 ) ;;
esac

jellyfin_deps=(at libsqlite3-0 libfontconfig1 libfreetype6 libssl1.1)

pkg_dependencies="${ffmpeg_deps[*]} ${jellyfin_deps[*]}"

#=================================================
# PERSONAL HELPERS
#=================================================

install_jellyfin_packages() {
	# In case of a new version, the url change from
	# https://repo.jellyfin.org/releases/server/debian/versions/stable/server/X.X.X/jellyfin-server_X.X.X-1_$YNH_ARCH.deb to
	# https://repo.jellyfin.org/archive/debian/stable/X.X.X/server/jellyfin-server_X.X.X-1_$YNH_ARCH.deb
	for pkg in web server; do
		src_url=$(grep 'SOURCE_URL=' "$YNH_APP_BASEDIR/conf/$pkg.$debian.$YNH_ARCH.src" | cut -d= -f2-)
		if ! curl --output /dev/null --silent --head --fail "$src_url"; then
			ynh_replace_string \
				--match_string="releases/server/debian/versions/stable/$pkg/$version/" \
				--replace_string="archive/debian/stable/$version/$pkg/" \
				--target_file="$YNH_APP_BASEDIR/conf/$pkg.$debian.$YNH_ARCH.src"
		fi
	done

	# Create the temporary directory
	tempdir="$(mktemp -d)"

	# Download the deb files
	ynh_setup_source --dest_dir=$tempdir --source_id="ffmpeg.$debian.$YNH_ARCH"
	ynh_setup_source --dest_dir=$tempdir --source_id="server.$debian.$YNH_ARCH"
	ynh_setup_source --dest_dir=$tempdir --source_id="web.$debian.$YNH_ARCH"

	# Install the packages
	ynh_exec_warn_less dpkg --force-confdef --force-confnew -i $tempdir/jellyfin-web.deb
	ynh_exec_warn_less dpkg --force-confdef --force-confnew -i $tempdir/jellyfin-ffmpeg5.deb
	ynh_exec_warn_less dpkg --force-confdef --force-confnew -i $tempdir/jellyfin-server.deb

	ynh_secure_remove --file="$tempdir"

	# The doc says it should be called only once,
	# but the code says multiple calls are supported.
	# Also, they're already installed so that should be quasi instantaneous.
	ynh_install_app_dependencies \
		jellyfin-web="$pkg_version" \
		jellyfin-ffmpeg5="$ffmpeg_pkg_version-$debian" \
		jellyfin-server="$pkg_version"
}

open_jellyfin_discovery_ports() {
	discovery_service=$discovery
	discovery_client=$discovery

	if [ "$discovery" -eq 1 ]; then

		# Open port $discovery_service_port for service auto-discovery
		if ynh_port_available --port=$discovery_service_port; then
			ynh_exec_warn_less yunohost firewall allow UDP $discovery_service_port
		else
			discovery_service=0
			ynh_print_warn --message="Port $discovery_service_port (for service auto-discovery) is not available. Continuing nonetheless."
		fi

		# Open port $discovery_client_port for client auto-discovery
		if ynh_port_available --port=$discovery_client_port; then
			ynh_exec_warn_less yunohost firewall allow UDP $discovery_client_port
		else
			discovery_client=0
			ynh_print_warn --message="Port $discovery_client_port (for client auto-discovery) is not available. Continuing nonetheless."
		fi
	fi

	ynh_app_setting_set --app="$app" --key=discovery_service --value="$discovery_service"
	ynh_app_setting_set --app="$app" --key=discovery_client --value="$discovery_client"
}

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================
