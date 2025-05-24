export PATHFILE="$HOME/.path"

# Build the PATH variable by concatenating each non-empty line in the file PATHFILE that does not start with "#"
if [ -f "${PATHFILE}" ]; then
	while IFS= read -r line; do
		if [[ ! "$line" =~ ^# && -n "$line" ]]; then
			if [[ -d "$line" ]]; then
				export PATH="${PATH}:${line}"
			fi
		fi
	done < "${PATHFILE}"
else
	echo "File ${PATHFILE} not found."
	exit 1
fi
