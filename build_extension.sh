#!/bin/bash
# Script to download external wheels needed for building Blender extension
# for Blender >= 4.2.
# This should be run on all supported platforms including
# linux-x86_64, windows-x86_64, macos-x86_64, macos_aarch64
# USAGE:
# bash build_extension.sh --source-dir SOURCE_DIR \
#                         [--blender-bin BLENDER_BIN]\
#                         [--build-dir BUILD_DIR]\
#                         [--export-dir EXPORT_DIR]\
#                         [--extra-wheels-directory EXTRA_WHEELS_DIR]

# Options:
# SOURCE_DIR: root directory of the batoms source code, e.g. ./batoms
# BLENDER_BIN: path to blender executable on the current platform, default 
# EXPORT_DIR: directory to export the generated zip files, default ./export
# BUILD_DIR: directory for building the blender extension, default ./build (will be cleaned during building).
# EXTRA_WHEELS_DIR: directory to wheels from other platforms.

# You may need to set other variables like C_INCLUDE_PATH and CC for compiling wheels from source.


set -e

# Default values

# SOURCE_DIR="${SOURCE_DIR:-$(pwd)}"


check_zip() {
    command -v zip >/dev/null 2>&1 || { echo >&2 "zip is required but it's not installed. Aborting."; exit 1; }
}

check_blender_binary() {
    if ! command -v $BLENDER_BIN &> /dev/null; then
        echo "Blender binary could not be found or is not executable: $BLENDER_BIN"
        exit 1
    fi
}

get_blender_python_binary() {
    $BLENDER_BIN -b --python-expr "import sys; print(f'###PYTHON_EXECUTABLE### {sys.executable} ###')" | grep '###PYTHON_EXECUTABLE###' | sed 's/###PYTHON_EXECUTABLE### \(.*\) ###/\1/'
}

check_blender_version() {
    local version=$($BLENDER_BIN -v | awk '/Blender/ {print $2}' | head -1)
    local major_version=$(echo "$version" | cut -d'.' -f1)
    local minor_version=$(echo "$version" | cut -d'.' -f2)
    if [ "$major_version" -lt 4 ] || { [ "$major_version" -eq 4 ] && [ "$minor_version" -lt 2 ]; }; then
        echo "Blender version must be >= 4.2. Current version: $version"
        exit 1
    fi
}

get_platform_string() {
    local blender_py=$(get_blender_python_binary)
    $blender_py <<EOF
import platform
import sys

os_name = platform.system()
arch = platform.machine()

if os_name == "Linux":
    if arch == "x86_64":
        print("linux_x64")
    else:
        print("unsupported")
elif os_name == "Darwin":
    if arch == "x86_64":
        print("macos_x64")
    elif arch == "arm64":
        print("macos_arm64")
    else:
        print("unsupported")
elif os_name in ["Windows", "Microsoft"]:
    print("windows_x64")
else:
    print("unsupported")
EOF
}



# Get factory versions of python packages, like numpy
get_blender_factory_packages() {
    local blender_py=$(get_blender_python_binary)
    $blender_py -m pip freeze
}

# Use pip wheel to download or compile wheels to the wheels dir
# Note this method would only produce wheels for the CURRENT PLATFORM
download_wheels() {
    local blender_py=$(get_blender_python_binary)
    local wheels_dir=$1
    local requirements=$2
    $blender_py -m pip wheel -w $wheels_dir -r $requirements
}

# Exclude package wheels that are already shipped with blender (e.g. numpy)
exclude_dependencies() {
    local blender_packages=$1
    local wheels_dir=$2
    echo "$blender_packages" | while IFS= read -r line; do
        package=$(echo "$line" | cut -d'=' -f1)
        rm -f "${wheels_dir}/${package}"*.whl
    done
}

update_manifest() {
    local wheels_dir=$1
    local blender_py=$(get_blender_python_binary)
    local toml_header="# blender_manifest.toml generated by build_extension.sh, please do not manually modify\n"
    $blender_py <<EOF
import toml
import os
from pathlib import Path

template_path = Path("${BUILD_DIR}") / "blender_manifest.toml.template"
output_path = Path("${BUILD_DIR}") / "blender_manifest.toml"

with open(template_path, 'r') as f:
    manifest = toml.load(f)

wheels = []
for file in Path("${wheels_dir}").glob("*.whl"):
    wheels.append(f"./wheels/{file.name}")

manifest['wheels'] = wheels

toml_str = "${toml_header}" + toml.dumps(manifest)
with open(output_path, "w") as f:
    f.write(toml_str)
EOF
}

build_extension() {
    $BLENDER_BIN --command extension build \
		--source-dir ${BUILD_DIR} \
		--output-dir ${EXPORT_DIR} \
		--split-platform

    # If EXTRA_WHEELS_DIR not provided or empty,
    # delete zips that are not for the current platform
    if [ -z "${EXTRA_WHEELS_DIR}" ]; then
        platform_string=$(get_platform_string)
        if [ "$platform_suffix" == "unsupported" ]; then
            echo "Unsupported platform or architecture."
            exit 1
        fi
	echo "Extra wheels for other platforms not provided, will only build extension for current platform: $platform_string"
        for zip_file in ${EXPORT_DIR}/*.zip; do
            if [[ ! "$zip_file" == *"$platform_string".zip ]]; then
                rm -f "$zip_file"
            fi
        done
    else
	local num_wheels=-1
	# TODO: better to fetch label batoms from toml file
        for zip_file in ${EXPORT_DIR}/batoms-*.zip; do
            current_num_wheels=$(unzip -l "$zip_file" | awk '/wheels\/.*\.whl/ {print $NF}' | wc -l)
            if [ $num_wheels -eq -1 ]; then
                num_wheels=$current_num_wheels
            else
                if [ $current_num_wheels -ne $num_wheels ]; then
                    echo "Mismatch found in the number of wheels in extensions between platforms."
		    echo "Please check if $EXTRA_WHEEKS_DIR contains the correct wheel files."
		    echo "Will now abort."
                    exit 1
                fi
            fi
        done
    fi
    echo "Building complete. The following extensions can be found at ${EXPORT_DIR}"
}

usage() {
    echo "USAGE:"
    echo "bash build_extension.sh --source-dir SOURCE_DIR \\"
    echo "                        [--blender-bin BLENDER_BIN]\\"
    echo "                        [--build-dir BUILD_DIR]\\"
    echo "                        [--export-dir EXPORT_DIR]\\"
    echo "                        [--extra-wheels-directory EXTRA_WHEELS_DIR]"
    echo ""
    echo "Options:"
    echo "SOURCE_DIR: root directory of the batoms source code, e.g. ./batoms"
    echo "BLENDER_BIN: path to blender executable on the current platform, default "
    echo "EXPORT_DIR: directory to export the generated zip files, default ./export"
    echo "BUILD_DIR: directory for building the blender extension, default ./build (will be cleaned during building)."
    echo "EXTRA_WHEELS_DIR: directory to wheels from other platforms."
    echo ""
    echo "You may need to set other variables like C_INCLUDE_PATH and CC for compiling wheels from source."
    exit 1
}


main() {

    while [[ "$#" -gt 0 ]]; do
	case $1 in
            --blender-bin) BLENDER_BIN="$2"; shift ;;
	    --build-dir) BUILD_DIR="$2"; shift ;;
            --source-dir) SOURCE_DIR="$2"; shift ;;
            --export-dir) EXPORT_DIR="$2"; shift ;;
	    --extra-wheels-directory) EXTRA_WHEELS_DIR="$2"; shift ;;
            *) break ;;
	esac
	shift
    done

    if [ -z "$SOURCE_DIR" ]; then
        usage
    fi
    
    
    BLENDER_BIN="${BLENDER_BIN:-blender}"
    MANIFEST_TEMPLATE="${SOURCE_DIR}/blender_manifest.toml.template"
    BUILD_DIR="${BUILD_DIR:-$(pwd)/build}"
    WHEELS_DIR="${BUILD_DIR}/wheels"
    EXPORT_DIR="${EXPORT_DIR:-$(pwd)/export}"

    check_blender_binary && check_zip
    
    check_blender_version

    # Create directories
    mkdir -p "$BUILD_DIR"
    rm -rf "${BUILD_DIR:?}/*"
    mkdir -p "$EXPORT_DIR"
    mkdir -p "$WHEELS_DIR"
    cp -r "${SOURCE_DIR}/" "${BUILD_DIR}/"

    # Combine requirements
    local blender_factory_packages=$(get_blender_factory_packages)
    echo "${blender_factory_packages}" >> "${BUILD_DIR}/build_requirements.txt"

    # Filter and exclude the wheels
    download_wheels "$WHEELS_DIR" "${BUILD_DIR}/build_requirements.txt"
    exclude_dependencies "$blender_factory_packages" "$WHEELS_DIR"

    # TODO: check if we have good wheels support?
    # Include extra wheels if provided
    if [ -n "$EXTRA_WHEELS_DIR" ]; then
        cp -r "$EXTRA_WHEELS_DIR"/*.whl "$WHEELS_DIR"
    fi

    update_manifest "$WHEELS_DIR"
    build_extension
}

main "$@"
