#!/bin/sh
PARALLEL=2 # Number of parallel processes to run
SCRIPT=GetJobs.py
COMMAND="cp" # For testing
#PARAMS="<working directory> <output extension> <SQS queue> <AWS region> <command>"
PARAMS="/var/tmp .out batch-queue eu-west-1 $COMMAND"
yum update -y
wget -O $SCRIPT "<Replace this with a Signed URL to download the GetJobs.py script>"
for i in $(seq $PARALLEL)
do
    LOGFILE=./${SCRIPT}.$i.log
    echo "Starting $i of $PARALLEL - log file is $LOGFILE ..."
    nohup python ./$SCRIPT $PARAMS > $LOGFILE 2>&1 &
done
