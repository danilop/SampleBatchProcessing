#!/usr/bin/env python

import json
import os

from sys import argv, exit

import boto
import boto.s3
import boto.sqs

from boto.s3.key import Key
from boto.sqs.message import Message

def uploadDir(localDir, s3BucketName, s3InputPrefix, s3OutputPrefix, sqsQueueName, awsRegion):
    files = os.listdir(localDir)
    s3 = boto.s3.connect_to_region(awsRegion)
    s3Bucket = s3.get_bucket(s3BucketName)
    sqs = boto.sqs.connect_to_region(awsRegion)
    sqsQueue =  sqs.lookup(sqsQueueName)
    for fileName in files:
        localPath = os.path.join(localDir, fileName)
        remotePath = s3InputPrefix + fileName
        print "Uploading %s to s3://%s/%s ..." % (localPath, s3BucketName, remotePath)
        # Upload to S3
        key = Key(s3Bucket)
        key.key = remotePath
        key.set_contents_from_filename(localPath)
        # Send message to SQS
        print "Sending message to SQS queue ..."
        messageBody = json.dumps(['process', s3BucketName, s3InputPrefix, s3OutputPrefix, fileName])
        m = Message()
        m.set_body(messageBody)
        sqsQueue.write(m)
        print "Done!"
    print "All done!"

def main():
    if len(argv) < 6:
	print "Usage: %s <local directory> <S3 bucket> <S3 input prefix> <S3 output prefix> <SQS queue> <AWS region>" % argv[0]
        exit(1)
    localDir = argv[1]
    s3BucketName = argv[2]
    s3InputPrefix = argv[3]
    s3OutputPrefix = argv[4]
    sqsQueueName = argv[5]
    awsRegion = argv[6]
    uploadDir(localDir, s3BucketName, s3InputPrefix, s3OutputPrefix, sqsQueueName, awsRegion)

if __name__ == '__main__':

    main()
