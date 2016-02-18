# Sample Implementation of Batch Processing on Amazon Web Services (AWS)

This is a Sample Implementation for the [AWS Reference Architecture for Batch Processing](http://aws.amazon.com/architecture/).

Is is implemented in Python, using [boto](http://aws.amazon.com/sdkforpython/), and the new [AWS Command Line Interface (CLI)](http://aws.amazon.com/cli/).

Two tools are provided:
* SendJobs.py - to upload files from a (local) directory to S3 and put "job" requests to process those files as messages in an SQS queue
* GetJobs.py - to get "job" messages from an SQS queue and upload on S3 the outcome of the processing

The setup leverages [EC2](http://aws.amazon.com/ec2/) [Auto Scaling](http://aws.amazon.com/autoscaling/) to have a group of instances that is empty (i.e. no instance is running) when there are no "job" requests in the SQS queue and grows when there is the need.

## Tutorial

### Install AWS CLI

The new [AWS Command Line Interface (CLI) tool](http://aws.amazon.com/cli/)
is Python based, so you can install it using "pip"

    pip install awscli

or using "easy_install"

    easy_install awscli

Before using AWS CLI, you first need to specify your AWS account credentials and default AWS region as described
[here](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).

The awscli package includes a very useful command completion feature,
e.g. to enable tab completion for bash use the built-in command complete (not boot persistant):

    complete -C aws_completer aws

### Create an S3 Bucket to host input and output files

You can create a bucket from the [S3 web console](http://console.aws.amazon.com/s3/) or using the CLI:

    aws s3api create-bucket --bucket  <S3 Bucket Name> \
    --create-bucket-configuration '{ "location_constraint": <Your AWS Region, e.g. "eu-west-1"> }'

### Create an SQS Queue to centralize "job" requests

You can create a queue from the [SQS web console](http://console.aws.amazon.com/sqs/) or using the CLI:
The "VisibilityTimeout" is expressed in seconds and should be larger than the maximun processing time required for a "job".
It can eventually be increased for a single "job", but that is not part of this implementation.

    aws sqs create-queue --queue-name <SQS Queue Name> --attributes VisibilityTimeout=60

### Create a IAM Role to delegate access to processing instances

From the [IAM web console](http://console.aws.amazon.com/iam/) -> Roles -> Create Role -> 
Write a role name.Under "AWS Service Roles" select "Amazon EC2".
Select a "Custom Policy", write a policy name and see the "role.json" file
for a sample role giving access to an S3 bucket and an SQS queue.
You should replace "AWS Account", "S3 Bucket Name" and "SQS Queue Name" in the policy with yours.
Write down the Instance Profile ARN from the Summary tab, you'll need it later.

### Create Auto Scaling Launch Configuration

For this sample I'm using a default Amazon Linux EBS-backed AMI, you can take the AMI ID [here](http://aws.amazon.com/amazon-linux-ami)
The user data script provided automatically configures and run multiple parallel "GetJobs.py" scripts per node to get "job" from the queue and process them, uploading the final result back on S3. You probably need to edit the "user-data.sh" file before launching the following command.
Alternatively you can create your own AMI that starts one of more parallel "GetJobs.py" scripts at boot.

    aws autoscaling create-launch-configuration --launch-configuration-name asl-batch \
    --image-id <Amazon Linux AMI ID> --instance-type <EC2 Instance Type, e.g. t1.micro> \
    --iam-instance-profile <Instance Profile ARN> --user-data "`cat user-data.sh`"

If you want to be able to login into the instances launched by Auto Scaling you can add the following parametrs to the previous command

    --key-name <EC2 Key Pair for SSH login> --security-groups <EC2 Security Group allowing SSH access>

### Create Auto Scaling Group

    aws autoscaling create-auto-scaling-group --auto-scaling-group-name asg-batch \
    --launch-configuration-name asl-batch --min-size 0 \
    --max-size <Number of Instances to start when there are "jobs" in the SQS queue> \
    --availability-zones <All AZs in the region, \
    e.g. for "eu-west-1" you can use "eu-west-1a" "eu-west-1b" "eu-west-1c"> \
    --default-cooldown 300

### Create Auto Scaling "Up" Policy

    aws autoscaling put-scaling-policy --auto-scaling-group-name asg-batch --policy-name ash-batch-upscale-policy \
    --scaling-adjustment <Number of Instances to start when there are "jobs" in the SQS queue> \
    --adjustment-type ExactCapacity

Write down the "PolicyARN", you need it in the next step to set up the alarm.

### Create CloudWatch Alarm to trigger "Up" scaling Policy

    aws cloudwatch put-metric-alarm --alarm-name StartBatchProcessing --metric-name ApproximateNumberOfMessagesVisible \
    --namespace "AWS/SQS" --statistic Average --period 60  --evaluation-periods 2 --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold --dimensions Name=QueueName,Value=batch-queue \
    --alarm-actions <"Up" PolicyARN>

### Create Auto Scaling "Down" Policy

    aws autoscaling put-scaling-policy --auto-scaling-group-name asg-batch --policy-name ash-batch-downscale-policy \
    --scaling-adjustment 0 --adjustment-type ExactCapacity

Write down the "PolicyARN", you need it in the next step to set up the alarm.

### Create CloudWatch Alarm to trigger "Down" scaling Policy

    aws cloudwatch put-metric-alarm --alarm-name StopBatchProcessing --metric-name ApproximateNumberOfMessagesVisible \
    --namespace "AWS/SQS" --statistic Average --period 60  --evaluation-periods 2 --threshold 0 \
    --comparison-operator LessThanOrEqualToThreshold --dimensions Name=QueueName,Value=batch-queue \
    --alarm-actions <"Down" PolicyARN>

### Send the jobs uploading files from a directory

The directory can be local or on an EC2 instance.

    ./SendJobs.py <Directory> <S3 Bucket Name> input/ output/ <SQS Queue Name> <AWS Region, e.g. "eu-west-1">

To get help, run the tool without options

    ./SendJobs.py

After a few minutes the first CloudWatch Alarm should trigger the "Up" scaling Policy
to start EC2 Instances configured to consume "jobs" from the SQS queue.
When all "jobs" are processed and the SQS is "empty" the second CloudWatch Alarm should trigger
the "Down" scaling Policy to shutdown and terminate the EC2 Instances.
You should find the output of the processing in the S3 bucket under the "ouput/" prefix.

### Change the Launch Configuration of an Auto Scaling Group

If later on you need to change the Launch Configuration create a new one and update the Auto Scaling Group, e.g.

    aws autoscaling update-auto-scaling-group --launch-configuration-name asl-batch-v2 \
    --auto-scaling-group-name asg-batch
