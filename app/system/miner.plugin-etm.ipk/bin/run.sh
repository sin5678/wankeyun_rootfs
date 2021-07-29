#!/bin/sh

PLUGIN_NAME="plugin-etm"
MAIN_EXE_NAME="etm_monitor"

PLUGIN_DIR="/app/system/miner.${PLUGIN_NAME}.ipk"
PLUGIN_BIN_DIR="${PLUGIN_DIR}/bin"
PLUGIN_CONF_DIR="${PLUGIN_DIR}/conf"
PLUGIN_LIB_DIR="${PLUGIN_DIR}/lib"

# Note: Do not add & to make it run background.
export LD_LIBRARY_PATH=$PLUGIN_LIB_DIR:$LD_LIBRARY_PATH
cd ${PLUGIN_BIN_DIR} && ./${MAIN_EXE_NAME}

