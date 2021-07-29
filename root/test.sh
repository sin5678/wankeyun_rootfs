#!/bin/sh
killall factory_app
export LD_LIBRARY_PATH=/thunder/lib
export PATH=$PATH:/thunder/bin
factory_app
