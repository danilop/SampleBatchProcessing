#!/usr/bin/env python

import json
import os
import subprocess
import signal

from sys import argv, exit

import boto
import boto.s3
import boto.sqs

from boto.s3.key import Key
from boto.sqs.message import Message

def getJobs(workDir, outputExtension, sqsQueueName, awsRegion, command):
    s3 = boto.s3.connect_to_region(awsRegion)
    sqs = boto.sqs.connect_to_region(awsRegion)
    sqsQueue =  sqs.lookup(sqsQueueName)
    while (True):
	print "Getting messages from SQS queue..."
        messages = sqsQueue.get_messages(wait_time_seconds=20)
        if messages:
            for m in messages:
                print m.get_body()
                job = json.loads(m.get_body())
                print "Message received: '%s'" % job
                action = job[0]
                if action == 'process':
                    s3BucketName = job[1]
                    s3InputPrefix = job[2]
                    s3OutputPrefix = job[3]
                    fileName = job[4]
                    status = process(s3, s3BucketName, s3InputPrefix, s3OutputPrefix, fileName,
			workDir, outputExtension, command)
                    if (status):
			print "Message processed correctly ..."
                        m.delete()
			print "Message deleted"
                
def process(s3, s3BucketName, s3InputPrefix, s3OutputPrefix, fileName, workDir, outputExtension, command):
    s3Bucket = s3.get_bucket(s3BucketName)
    localInputPath = os.path.join(workDir, fileName)
    localOutputPath = localInputPath + outputExtension
    remoteInputPath = s3InputPrefix + fileName
    remoteOutputPath = s3OutputPrefix + fileName + outputExtension
    print "Downloading %s from s3://%s/%s ..." % (localInputPath, s3BucketName, remoteInputPath)
    key = s3Bucket.get_key(remoteInputPath)
    key.get_contents_to_filename(localInputPath)
    full_command = [command, localInputPath, localOutputPath]
    print "Executing: %s" % ' '.join(full_command)
    returncode = subprocess.call(full_command)
    if returncode != 0:
        print "Return Code not '0'!"
	return False
    print "Uploading %s to s3://%s/%s ..." % (localOutputPath, s3BucketName, remoteOutputPath)
    key = Key(s3Bucket)
    key.key = remoteOutputPath
    key.set_contents_from_filename(localOutputPath)
    return True

def signal_handler(signal, frame):
    print "Exiting..."
    exit(0)

def main():
    if len(argv) < 4:
	print "Usage: %s <working directory> <output extension> <SQS queue> <AWS region> <command>" % argv[0]
        exit(1)
    workDir = argv[1]
    outputExtension = argv[2]
    sqsQueueName = argv[3]
    awsRegion = argv[4]
    command = argv[5]
    getJobs(workDir, outputExtension, sqsQueueName, awsRegion, command)

if __name__ == '__main__':

    signal.signal(signal.SIGINT, signal_handler)
    main()

