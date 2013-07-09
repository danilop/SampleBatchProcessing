#!/bin/sh
PARALLEL=2 # Number of parallel processes to run
SCRIPT=GetJobs.py
COMMAND="cp" # For testing
#PARAMS="<working directory> <output extension> <SQS queue> <AWS region> <command>"
PARAMS="/var/tmp .out batch-queue eu-west-1 $COMMAND"
yum update -y
wget -O $SCRIPT "https://batch-proc.s3.amazonaws.com/GetJobs.py?AWSAccessKeyId=AKIAI7XQAT4EZOA7C45Q&Expires=1404897450&Signature=Lt3Z1BGV%2BBb2eoR%2FSBnSt7%2F2QsM%3D"
for i in $(seq $PARALLEL)
do
    LOGFILE=./${SCRIPT}.$i.log
    echo "Starting $i of $PARALLEL - log file is $LOGFILE ..."
    nohup python ./$SCRIPT $PARAMS > $LOGFILE 2>&1 &
done
