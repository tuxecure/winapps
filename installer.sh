#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

MAKEDEMO=0
USEDEMO=0

. "${DIR}/install/inquirer.sh"

INSTALLED_EXES=()

function waUsage() {
	echo 'Usage:
  ./installer.sh --user    # Install everything in ${HOME}
  ./installer.sh --system  # Install everything in /usr'
	exit
}

function waNoSudo() {
	echo 'You are attempting to switch from a --system install to a --user install.
Please run "./installer.sh --system --uninstall" first.'
	exit
}

function waInstall() {
	${SUDO} mkdir -p "${SYS_PATH}/apps"
	${SUDO} mkdir -p "${ICO_PATH}"
	. "${DIR}/bin/winapps" install
}

function waFindInstalled() {
	echo -n "  Checking for installed apps in RDP machine (this may take a while)..."
	if [ $USEDEMO != 1 ]; then
		rm -f ${HOME}/.local/share/winapps/installed.bat
		rm -f ${HOME}/.local/share/winapps/installed.tmp
		rm -f ${HOME}/.local/share/winapps/installed
		rm -f ${HOME}/.local/share/winapps/detected
		cp "${DIR}/install/ExtractPrograms.ps1" ${HOME}/.local/share/winapps/ExtractPrograms.ps1
		for F in $(ls "${DIR}/apps"); do
			if [[ -d "${DIR}/apps/${F}" ]]; then
			    . "${DIR}/apps/${F}/info"
			    [[ ${F} != "windows" ]] && echo "IF EXIST \"${WIN_EXECUTABLE}\" ECHO ${F} >> \\\\tsclient\\home\\.local\\share\\winapps\\installed.tmp" >> ${HOME}/.local/share/winapps/installed.bat
			fi
		done;
		echo "powershell.exe -ExecutionPolicy Bypass -File \\\\tsclient\\home\\.local\\share\\winapps\\ExtractPrograms.ps1 > \\\\tsclient\home\\.local\\share\\winapps\\detected" >> ${HOME}/.local/share/winapps/installed.bat
		echo "RENAME \\\\tsclient\\home\\.local\\share\\winapps\\installed.tmp installed" >> ${HOME}/.local/share/winapps/installed.bat
		xfreerdp "${HOME}/.config/winapps/${RDP_HOSTNAME:-RDPWindows}.rdp" /v:${RDP_IP} +auto-reconnect +home-drive -wallpaper /span /wm-class:"RDPInstaller" /app:"C:\Windows\System32\cmd.exe" /app-cmd:"/C \\\\tsclient\\home\\.local\\share\\winapps\\installed.bat" 1> /dev/null 2>&1 &
		COUNT=0
		while [ ! -f "${HOME}/.local/share/winapps/installed" ]; do
			sleep 5
			echo $((15-${COUNT}))
			COUNT=$((COUNT + 1))
			if (( COUNT == 15 )); then
				echo " Finished."
				echo ""
				echo "The RDP connection failed to connect or run. Please confirm FreeRDP can connect with:"
				echo "	bin/winapps check"
				echo ""
				echo "If it cannot connect, this is most likely due to:"
				echo "	- You need to accept the security cert the first time you connect (with 'check')"
				echo "	- Not enabling RDP in the Windows VM"
				echo "	- Not being able to connect to the IP of the VM"
				echo "	- Incorrect user credentials in winapps.conf"
				echo "	- Not merging install/RDPApps.reg into the VM"
				exit
			fi
		done
		if [ $MAKEDEMO = 1 ]; then
			rm -rf /tmp/winapps_demo
			cp -a ${HOME}/.local/share/winapps /tmp/winapps_demo
			exit
		fi
	else
		rm -rf ${HOME}/.local/share/winapps
		cp -a /tmp/winapps_demo ${HOME}/.local/share/winapps
		#sleep 3
	fi
	echo " Finished."
}

function waConfigureApp() {
		BIN=${1}
		if [ ${USEDEMO} != 1 ]; then
			${SUDO} rm -f "${APP_PATH}/winapps.${BIN}.desktop"
			${SUDO} envsubst <"${DIR}/install/desktopfile" > "${APP_PATH}/winapps.${BIN}.desktop"

			${SUDO} rm -f "${BIN_PATH}/${BIN}"
			${SUDO} envsubst <"${DIR}/install/binfile" > "${BIN_PATH}/${BIN}"
			${SUDO} chmod a+x "${BIN_PATH}/${BIN}"
		fi
		echo " Finished."
}

function waConfigureApps() {
	APPS=()
	for F in $(cat "${HOME}/.local/share/winapps/installed" |sed 's/\r/\n/g'); do
		[[ -d "${DIR}/apps/${F}" ]] && . "${DIR}/apps/${F}/info"
		APPS+=("${FULL_NAME} (${F})")
		INSTALLED_EXES+=("$(echo "${WIN_EXECUTABLE##*\\}" |tr '[:upper:]' '[:lower:]')")
	done
	IFS=$'\n' APPS=($(sort <<<"${APPS[*]}"))
	unset IFS
	OPTIONS=("Set up all detected pre-configured applications" "Select which pre-configured applications to set up" "Do not set up any pre-configured applications")
	menuFromArr APP_INSTALL "How would you like to handle WinApps pre-configured applications?" "${OPTIONS[@]}"
	if [ "${APP_INSTALL}" = "Select which pre-configured applications to set up" ]; then
		checkbox_input "Which pre-configured apps would you like to set up?" APPS SELECTED_APPS
		echo "" > "${HOME}/.local/share/winapps/installed"
		for F in "${SELECTED_APPS[@]}"; do
			APP="${F##*(}"
			APP="${APP%%)}"
			echo "${APP}" >> "${HOME}/.local/share/winapps/installed"
		done
	fi	
	${SUDO} cp "${DIR}/bin/winapps" "${BIN_PATH}/winapps"
	COUNT=0
	if [ "${APP_INSTALL}" != "Do not set up any pre-configured applications" ]; then
		for F in $(cat "${HOME}/.local/share/winapps/installed" |sed 's/\r/\n/g'); do
			COUNT=$((COUNT + 1))
			${SUDO} cp -r "apps/${F}" "${SYS_PATH}/apps"
			set -a
			ICON="winapps-${F}";
			${SUDO} mv "${SYS_PATH}/apps/${F}/icon.svg" "${ICO_PATH}/${ICON}.svg"
			[[ -d "${SYS_PATH}/apps/${F}" ]] && . "${SYS_PATH}/apps/${F}/info"
			echo -n "  Configuring ${NAME}..."
			MIMETYPE="MimeType=${MIME_TYPES}"
			waConfigureApp "${F}"
			set +a
		done
	fi
	rm -f "${HOME}/.local/share/winapps/installed"
	rm -f "${HOME}/.local/share/winapps/installed.bat"
	if (( $COUNT == 0 )); then
		echo "	No configured applications."
	fi
}

function waConfigureDetectedApps() {
	if [ -f "${HOME}/.local/share/winapps/detected" ]; then
		sed -i 's/\r//g' "${HOME}/.local/share/winapps/detected"
		. "${HOME}/.local/share/winapps/detected"
		APPS=()
		for I in "${!NAMES[@]}"; do
			EXE=${EXES[$I]##*\\}
			EXE_LOWER=$(echo "${EXE}" |tr '[:upper:]' '[:lower:]')
			if ( dlm=$'\x1F' ; IFS="$dlm" ; [[ "$dlm${INSTALLED_EXES[*]}$dlm" != *"$dlm${EXE_LOWER}$dlm"* ]] ) ; then
				APPS+=("${NAMES[$I]} (${EXE})")
			fi
		done
		IFS=$'\n' APPS=($(sort <<<"${APPS[*]}"))
		unset IFS
		OPTIONS=("Set up all detected applications" "Select which applications to set up" "Do not set up any applications")
		menuFromArr APP_INSTALL "How would you like to handle other detected applications?" "${OPTIONS[@]}"
		if [ "${APP_INSTALL}" = "Select which applications to set up" ]; then
			checkbox_input "Which other apps would you like to set up?" APPS SELECTED_APPS
			echo "" > "${HOME}/.local/share/winapps/installed"
			for F in "${SELECTED_APPS[@]}"; do
				EXE="${F##*(}"
				EXE="${EXE%%)}"
				APP="${F% (*}"
				echo "${EXE}|${APP}" >> "${HOME}/.local/share/winapps/installed"
			done
		elif [ "${APP_INSTALL}" = "Set up all detected applications" ]; then
			for I in "${!EXES[@]}"; do
				EXE=${EXES[$I]##*\\}
				echo "${EXE}|${NAMES[$I]}" >> "${HOME}/.local/share/winapps/installed"
			done
		fi
		COUNT=0
		if [ -f "${HOME}/.local/share/winapps/installed" ]; then
			while read LINE; do
				EXE="${LINE%|*}"
				NAME="${LINE#*|}"
				for I in "${!NAMES[@]}"; do
					if [ "${NAME}" = "${NAMES[$I]}" ] && [[ "${EXES[$I]}" == *"\\${EXE}" ]]; then
						EXE=$(echo "${EXE}" |tr '[:upper:]' '[:lower:]')
						${SUDO} mkdir -p "${SYS_PATH}/apps/${EXE}"
						echo "# GNOME shortcut name
NAME=\"${NAME}\"

# Used for descriptions and window class
FULL_NAME=\"${NAME}\"

# The executable inside windows
WIN_EXECUTABLE=\"${EXES[$I]}\"

# GNOME categories
CATEGORIES=\"WinApps\"

" > "${SYS_PATH}/apps/${EXE}/info"
						set -a
						ICON="${ICO_PATH}/winapps-${EXE}.ico"
						echo "${ICONS[$I]}" | base64 -d > "${ICON}"
						. "${SYS_PATH}/apps/${EXE}/info"
						echo -n "  Configuring ${NAME}..."
						waConfigureApp "${EXE}"
						set +a
						COUNT=$((COUNT + 1))
					fi
				done
			done < "${HOME}/.local/share/winapps/installed"
			rm -f "${HOME}/.local/share/winapps/installed"
		fi
		rm -f "${HOME}/.local/share/winapps/installed.bat"
		if (( $COUNT == 0 )); then
			echo "	No configured applications."
		fi
	fi
}


function waConfigureWindows() {
	echo -n "  Configuring Windows..."
	if [ ${USEDEMO} != 1 ]; then
		${SUDO} rm -f "${APP_PATH}/winapps.windows.desktop"
		${SUDO} cp -r "apps/windows" "${SYS_PATH}/apps"
		set -a
		ICON="winapps-windows"
		${SUDO} mv "${SYS_PATH}/apps/windows/icon.svg" "${ICO_PATH}/${ICON}.svg"
		. "${SYS_PATH}/apps/windows/info"
		waConfigureApp "windows"
		set +a

	fi
	echo " Finished."
}

function waUninstallUser() {
	rm -f "${HOME}/.local/bin/winapps"
	rm -rf "${HOME}/.local/share/winapps"
	for F in $(grep -l -d skip "winapps" "${APP_PATH}/winapps."*); do
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
	for F in $(grep -l -d skip "winapps" "${BIN_PATH}/"*); do
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
	for F in $(ls "${ICO_PATH}/winapps-"*); do
		echo -n "  Removing ${F}..."
		${SUDO} rm "${F}"
		echo " Finished."
	done
}

function waUninstallSystem() {
	${SUDO} rm -f "/usr/local/bin/winapps"
	${SUDO} rm -rf "/usr/local/share/winapps"
	for F in $(grep -l -d skip "bin/winapps" "/usr/share/applications/"*); do
		if [ -z "${SUDO}" ]; then
			waNoSudo
		fi
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
	for F in $(grep -l -d skip "bin/winapps" "/usr/local/bin/"*); do
		if [ -z "${SUDO}" ]; then
			waNoSudo
		fi
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
}

if [ -z "${1}" ]; then
	OPTIONS=(User System)
	menuFromArr INSTALL_TYPE "Would you like to install for the current user or the whole system?" "${OPTIONS[@]}"
elif [ "${1}" = '--user' ]; then
	INSTALL_TYPE='User'
elif [ "${1}" = '--system' ]; then
	INSTALL_TYPE='System'
else
	waUsage
fi

if [ "${INSTALL_TYPE}" = 'User' ]; then
	SUDO=""
	BIN_PATH="${HOME}/.local/bin"
	APP_PATH="${HOME}/.local/share/applications"
	ICO_PATH="${HOME}/.local/share/icons"
	SYS_PATH="${HOME}/.local/share/winapps"

	case ":${PATH}:" in
	    *:"${HOME}/.local/bin":*)
		;;
	    *) EXEC="${BIN_PATH}/";;
	esac

	if [ -n "${2}" ]; then
		if [ "${2}" = '--uninstall' ]; then
			# Uninstall
			echo "Uninstalling..."
			waUninstallUser
			exit
		else
			usage
		fi
	fi
elif [ "${INSTALL_TYPE}" = 'System' ]; then
	SUDO="sudo"
	sudo ls > /dev/null
	BIN_PATH="/usr/local/bin"
	APP_PATH="/usr/share/applications"
	ICO_PATH="/usr/share/icons"
	SYS_PATH="/usr/local/share/winapps"
	if [ -n "${2}" ]; then
		if [ "${2}" = '--uninstall' ]; then
			# Uninstall
			echo "Uninstalling..."
			waUninstallSystem
			exit
		else
			usage
		fi
	fi
fi

echo "Removing any old configurations..."
[[ -f ${HOME}/.local/bin/winapps ]] && waUninstallUser
[[ -f /usr/local/bin/winapps ]] && waUninstallSystem

echo "Installing..."

# Inititialize
waInstall

# Check for installed apps
waFindInstalled

# Install windows
waConfigureWindows

# Configure apps
waConfigureApps
waConfigureDetectedApps

echo "Installation complete."
