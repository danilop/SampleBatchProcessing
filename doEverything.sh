#!/bin/bash
## This script breaks out some of the bash commands
## listed in the README.md file to be easier to
## follow along in class
##
## \author Hans J. Johson
## Tutorial
### Install AWS CLI

AWS_COMMAND=$(which aws)
if [ ! -f ${AWS_COMMAND} ]; then
  echo "ERROR: Missing aws commands, follow instructions in README.md"
  exit 2
fi

if ! $(python -c "import boto.sqs" &> /dev/null); then
   echo "ERROR: boto libary for aws services not installed in python" >&2
   exit 2
fi
# TODO: Test for awscli
#    pip install awscli
complete -C aws_completer aws

#####################################################
### Create an S3 Bucket to host input and output files
#You can create a bucket from the [S3 web console](http://console.aws.amazon.com/s3/) or using the CLI:
S3_BUCKET_NAME="hjtest2"      ##<S3 Bucket Name> ## Make all lower case letters
YOUR_AWS_REGION="us-east-1"   ## <Your AWS Region, e.g. "eu-west-1">
 aws s3 mb s3://${S3_BUCKET_NAME} \
   --region ${YOUR_AWS_REGION}
  if [ $? -ne 0 ]; then
    echo "FAIL: create bucket"
  fi

#####################################################
### Create an SQS Queue to centralize "job" requests
SQS_QUEUE_NAME="batch-queue"  ## <SQS Queue Name>
  aws sqs create-queue \
    --queue-name ${SQS_QUEUE_NAME} \
    --attributes VisibilityTimeout=60


#####################################################
### Create a IAM Role to delegate access to processing instances

## NOTE: THIS NEEDS TO BE DONE FROM AWS web console
#From the [IAM web console](http://console.aws.amazon.com/iam/) -> Roles -> Create Role -> 
#Write a role name.Under "AWS Service Roles" select "Amazon EC2".
#Select a "Custom Policy", write a policy name and see the "role.json" file
#for a sample role giving access to an S3 bucket and an SQS queue.
#You should replace "AWS Account", "S3 Bucket Name" and "SQS Queue Name" in the policy with yours.
#Write down the Instance Profile ARN from the Summary tab, you'll need it later.

INSTANCE_PROFILE_ARN="arn:aws:iam::236198936632:instance-profile/HansDLTRole"

#####################################################
### Create Auto Scaling Launch Configuration
LAUNCH_CONFIGURATION_NAME="asl-batch" 
LINUX_AMI_ID=ami-146e2a7c ## These are region specific
INSTANCE_TYPE=m3.medium   ## The instance profile to launch EC2 Instance Type, e.g. t1.micro

  aws autoscaling create-launch-configuration \
    --launch-configuration-name ${LAUNCH_CONFIGURATION_NAME} \
    --image-id ${LINUX_AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --iam-instance-profile ${INSTANCE_PROFILE_ARN} \
    --user-data "`cat user-data.sh`"

#If you want to be able to login into the instances launched by Auto Scaling you can add the following parametrs to the previous command
#    --key-name <EC2 Key Pair for SSH login> \
#    --security-groups <EC2 Security Group allowing SSH access>

#####################################################
### Create Auto Scaling Group
AUTO_SCALING_GROUP_NAME="asg-batch2" ## 
NUM_INSTANCES_TO_START=3 ## <Number of Instances to start when there are "jobs" in the SQS queue>

## NOTE: You must restrict your AZ's to those available in your VPC
AZ_IN_YOUR_DEFAULT_VPC="us-east-b us-east-c" ## All AZs in the region,
##  e.g. for "eu-west-1" you can use "eu-west-1a" "eu-west-1b" "eu-west-1c"
  aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name ${AUTO_SCALING_GROUP_NAME} \
    --launch-configuration-name ${LAUNCH_CONFIGURATION_NAME} \
    --min-size 0 \
    --max-size ${NUM_INSTANCES_TO_START} \
    --availability-zones ${AZ_IN_YOUR_DEFAULT_VPC} \
    --default-cooldown 300

#####################################################
### Create Auto Scaling "Up" Policy
AUTO_SCALE_UP_POLICY_NAME="ash-batch-upscale-policy"
NUM_JOBS_TO_UPSCALE=2
  aws autoscaling put-scaling-policy \
    --auto-scaling-group-name ${AUTO_SCALING_GROUP_NAME} \
    --policy-name ${AUTO_SCALE_UP_POLICY_NAME} \
    --scaling-adjustment ${NUM_JOBS_TO_UPSCALE} \
    --adjustment-type ExactCapacity |tee UP_POLICY_ARN.log 2>&1

# HACK TO GET the policy from script
UP_POLICY_ARN=$(cat UP_POLICY_ARN.log |grep PolicyARN| awk -F\" '{print $4'})
#Write down the "PolicyARN", you need it in the next step to set up the alarm.

### Create CloudWatch Alarm to trigger "Up" scaling Policy
  aws cloudwatch put-metric-alarm \
    --alarm-name StartBatchProcessing \
    --metric-name ApproximateNumberOfMessagesVisible \
    --namespace "AWS/SQS" \
    --statistic Average \
    --period 60  \
    --evaluation-periods 2 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=QueueName,Value=batch-queue \
    --alarm-actions ${UP_POLICY_ARN}

### Create Auto Scaling "Down" Policy
AUTO_SCALE_DOWN_POLICY_NAME="ash-batch-downscale-policy"
  aws autoscaling put-scaling-policy \
    --auto-scaling-group-name ${AUTO_SCALING_GROUP_NAME} \
    --policy-name ${AUTO_SCALE_DOWN_POLICY_NAME} \
    --scaling-adjustment 0 \
    --adjustment-type ExactCapacity |tee DOWN_POLICY_ARN.log 2>&1

DOWN_POLICY_ARN=$(cat DOWN_POLICY_ARN.log |grep PolicyARN| awk -F\" '{print $4'})

#Write down the "PolicyARN", you need it in the next step to set up the alarm.

### Create CloudWatch Alarm to trigger "Down" scaling Policy
  aws cloudwatch put-metric-alarm \
    --alarm-name StopBatchProcessing \
    --metric-name ApproximateNumberOfMessagesVisible \
    --namespace "AWS/SQS" \
    --statistic Average \
    --period 60  \
    --evaluation-periods 2 \
    --threshold 0 \
    --comparison-operator LessThanOrEqualToThreshold \
    --dimensions Name=QueueName,Value=batch-queue \
    --alarm-actions ${DOWN_POLICY_ARN}

### Send the jobs uploading files from a directory

#The directory can be local or on an EC2 instance.
#
#    ./SendJobs.py <Directory> <S3 Bucket Name> input/ output/ <SQS Queue Name> <AWS Region, e.g. "eu-west-1">
#
#To get help, run the tool without options
#
#    ./SendJobs.py
#
#After a few minutes the first CloudWatch Alarm should trigger the "Up" scaling Policy
#to start EC2 Instances configured to consume "jobs" from the SQS queue.
#When all "jobs" are processed and the SQS is "empty" the second CloudWatch Alarm should trigger
#the "Down" scaling Policy to shutdown and terminate the EC2 Instances.
#You should find the output of the processing in the S3 bucket under the "ouput/" prefix.
#
### Change the Launch Configuration of an Auto Scaling Group
#
#If later on you need to change the Launch Configuration create a new one and update the Auto Scaling Group, e.g.
#
#  aws autoscaling update-auto-scaling-group \
#    --launch-configuration-name ${LAUNCH_CONFIGURATION_NAME}-v2 \
#    --auto-scaling-group-name ${AUTO_SCALING_GROUP_NAME}

