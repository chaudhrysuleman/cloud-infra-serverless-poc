import os
import json
import pulumi
import pulumi_aws as aws

# --- Fetch Current AWS Account ID ---
aws_caller_identity = aws.get_caller_identity()
account_id = aws_caller_identity.account_id

# ==========================================
# 1. NETWORKING (VPC, Subnets, Gateway)
# ==========================================

# VPC
vpc = aws.ec2.Vpc("main-vpc",
    cidr_block="10.0.0.0/16",
    enable_dns_hostnames=True,
    enable_dns_support=True,
    tags={"Name": "poc-custom-vpc"}
)

# Internet Gateway
igw = aws.ec2.InternetGateway("internet-gateway",
    vpc_id=vpc.id,
    tags={"Name": "poc-igw"}
)

# Public Subnet (EC2 hosting)
public_subnet = aws.ec2.Subnet("public-subnet",
    vpc_id=vpc.id,
    cidr_block="10.0.1.0/24",
    map_public_ip_on_launch=True,
    availability_zone="eu-north-1a",
    tags={"Name": "poc-public-subnet"}
)

# Private Subnets (Multi-AZ RDS)
private_subnet_1 = aws.ec2.Subnet("private-subnet-1",
    vpc_id=vpc.id,
    cidr_block="10.0.2.0/24",
    availability_zone="eu-north-1a",
    tags={"Name": "poc-private-subnet-1"}
)

private_subnet_2 = aws.ec2.Subnet("private-subnet-2",
    vpc_id=vpc.id,
    cidr_block="10.0.3.0/24",
    availability_zone="eu-north-1b",
    tags={"Name": "poc-private-subnet-2"}
)

# Route Table for Public Subnet
public_rt = aws.ec2.RouteTable("public-rt",
    vpc_id=vpc.id,
    routes=[
        aws.ec2.RouteTableRouteArgs(
            cidr_block="0.0.0.0/0",
            gateway_id=igw.id,
        )
    ],
    tags={"Name": "poc-public-route-table"}
)

# Route Table Association
public_rt_assoc = aws.ec2.RouteTableAssociation("public-rt-association",
    subnet_id=public_subnet.id,
    route_table_id=public_rt.id
)

# ==========================================
# 2. SECURITY GROUPS (Firewalls)
# ==========================================

# EC2 Security Group (Port 80 HTTP, Port 22 SSH)
ec2_sg = aws.ec2.SecurityGroup("ec2-sg",
    vpc_id=vpc.id,
    description="Security group for application EC2 host",
    ingress=[
        aws.ec2.SecurityGroupIngressArgs(
            protocol="tcp",
            from_port=80,
            to_port=80,
            cidr_blocks=["0.0.0.0/0"],
            description="Allow HTTP public traffic"
        ),
        aws.ec2.SecurityGroupIngressArgs(
            protocol="tcp",
            from_port=22,
            to_port=22,
            cidr_blocks=["0.0.0.0/0"], # Restrict to specific IP in production
            description="Allow SSH access"
        )
    ],
    egress=[
        aws.ec2.SecurityGroupEgressArgs(
            protocol="-1",
            from_port=0,
            to_port=0,
            cidr_blocks=["0.0.0.0/0"],
            description="Allow all outbound traffic"
        )
    ],
    tags={"Name": "poc-ec2-security-group"}
)

# RDS Security Group (Port 5432 ingress restricted to EC2 SG)
rds_sg = aws.ec2.SecurityGroup("rds-sg",
    vpc_id=vpc.id,
    description="Security group for private PostgreSQL database",
    ingress=[
        aws.ec2.SecurityGroupIngressArgs(
            protocol="tcp",
            from_port=5432,
            to_port=5432,
            security_groups=[ec2_sg.id],
            description="Allow connections from EC2 app server only"
        )
    ],
    egress=[
        aws.ec2.SecurityGroupEgressArgs(
            protocol="-1",
            from_port=0,
            to_port=0,
            cidr_blocks=["0.0.0.0/0"]
        )
    ],
    tags={"Name": "poc-rds-security-group"}
)

# ==========================================
# 3. STORAGE & MESSAGING (S3, SNS, SQS)
# ==========================================

# Private S3 Bucket for Invoices
s3_bucket = aws.s3.BucketV2("invoices-bucket",
    bucket=f"suleman-parcels-invoices-{account_id}",
    force_destroy=True,
    tags={"Name": "poc-parcels-invoices"}
)

s3_ownership = aws.s3.BucketOwnershipControls("invoices-bucket-ownership",
    bucket=s3_bucket.id,
    rule=aws.s3.BucketOwnershipControlsRuleArgs(
        object_ownership="BucketOwnerPreferred"
    )
)

s3_public_access_block = aws.s3.BucketPublicAccessBlock("invoices-bucket-public-block",
    bucket=s3_bucket.id,
    block_public_acls=True,
    block_public_policy=True,
    ignore_public_acls=True,
    restrict_public_buckets=True
)

# SNS Topic
sns_topic = aws.sns.Topic("order-placed-topic",
    name="order-placed-topic"
)

# SQS Queues
notification_queue = aws.sqs.Queue("notification-queue",
    name="notification-queue",
    message_retention_seconds=86400
)

invoice_queue = aws.sqs.Queue("invoice-queue",
    name="invoice-queue",
    message_retention_seconds=86400
)

delivery_queue = aws.sqs.Queue("delivery-queue",
    name="delivery-queue",
    message_retention_seconds=86400
)

# SQS Queue Subscriptions to SNS
sub_notify = aws.sns.TopicSubscription("sub-notification",
    topic=sns_topic.arn,
    protocol="sqs",
    endpoint=notification_queue.arn
)

sub_invoice = aws.sns.TopicSubscription("sub-invoice",
    topic=sns_topic.arn,
    protocol="sqs",
    endpoint=invoice_queue.arn
)

sub_delivery = aws.sns.TopicSubscription("sub-delivery",
    topic=sns_topic.arn,
    protocol="sqs",
    endpoint=delivery_queue.arn
)

# SQS Queue Policies to allow SNS write permissions
def generate_sqs_policy_json(queue_arn, sns_arn):
    return json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": "*",
            "Action": "sqs:SendMessage",
            "Resource": queue_arn,
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": sns_arn
                }
            }
        }]
    })

policy_notify = aws.sqs.QueuePolicy("policy-notification",
    queue_url=notification_queue.id,
    policy=pulumi.Output.all(notification_queue.arn, sns_topic.arn).apply(
        lambda args: generate_sqs_policy_json(args[0], args[1])
    )
)

policy_invoice = aws.sqs.QueuePolicy("policy-invoice",
    queue_url=invoice_queue.id,
    policy=pulumi.Output.all(invoice_queue.arn, sns_topic.arn).apply(
        lambda args: generate_sqs_policy_json(args[0], args[1])
    )
)

policy_delivery = aws.sqs.QueuePolicy("policy-delivery",
    queue_url=delivery_queue.id,
    policy=pulumi.Output.all(delivery_queue.arn, sns_topic.arn).apply(
        lambda args: generate_sqs_policy_json(args[0], args[1])
    )
)

# ==========================================
# 4. IAM ROLES (EC2 Service Profile)
# ==========================================

# EC2 Assume Role Policy
ec2_assume_role_policy = json.dumps({
    "Version": "2012-10-17",
    "Statement": [{
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
            "Service": "ec2.amazonaws.com"
        }
    }]
})

ec2_role = aws.iam.Role("poc-ec2-role",
    name="poc-ec2-role",
    assume_role_policy=ec2_assume_role_policy
)

# EC2 Inline Policies for S3, SNS, SQS
def generate_iam_policy_json(s3_arn, sns_arn, q1_arn, q2_arn, q3_arn):
    return json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["s3:*"],
                "Resource": [s3_arn, f"{s3_arn}/*"]
            },
            {
                "Effect": "Allow",
                "Action": ["sns:Publish"],
                "Resource": [sns_arn]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "sqs:ReceiveMessage",
                    "sqs:DeleteMessage",
                    "sqs:GetQueueAttributes",
                    "sqs:GetQueueUrl"
                ],
                "Resource": [q1_arn, q2_arn, q3_arn]
            }
        ]
    })

ec2_role_policy = aws.iam.RolePolicy("poc-ec2-policy",
    role=ec2_role.id,
    name="poc-ec2-policy",
    policy=pulumi.Output.all(
        s3_bucket.arn,
        sns_topic.arn,
        notification_queue.arn,
        invoice_queue.arn,
        delivery_queue.arn
    ).apply(lambda args: generate_iam_policy_json(args[0], args[1], args[2], args[3], args[4]))
)

ec2_instance_profile = aws.iam.InstanceProfile("poc-ec2-instance-profile",
    name="poc-ec2-instance-profile",
    role=ec2_role.name
)

# ==========================================
# 5. DATABASES (PostgreSQL RDS)
# ==========================================

rds_subnet_group = aws.rds.SubnetGroup("rds-subnet-group",
    name="poc-rds-subnet-group",
    subnet_ids=[private_subnet_1.id, private_subnet_2.id],
    tags={"Name": "poc-rds-subnet-group"}
)

postgres_db = aws.rds.Instance("postgres-db",
    identifier="poc-postgres-db",
    engine="postgres",
    engine_version="15",
    instance_class="db.t3.micro",
    allocated_storage=20,
    db_name="postgres",
    username="dbadmin",
    password="SecurePass123!", # Should be fetched via config.require_secret in prod
    db_subnet_group_name=rds_subnet_group.name,
    vpc_security_group_ids=[rds_sg.id],
    skip_final_snapshot=True,
    tags={"Name": "poc-postgres-database"}
)

# ==========================================
# 6. COMPUTE (EC2 Instance)
# ==========================================

# Key pair SSH resolution
ssh_key_path = os.path.expanduser("~/.ssh/id_ed25519_github.pub")
if not os.path.exists(ssh_key_path):
    ssh_key_path = os.path.expanduser("~/.ssh/gitlab_ed25519.pub")

with open(ssh_key_path, "r") as f:
    pub_key_content = f.read().strip()

key_pair = aws.ec2.KeyPair("ssh-key",
    key_name="poc-ssh-key",
    public_key=pub_key_content
)

# Query latest Ubuntu 22.04 LTS AMI
ubuntu_ami = aws.ec2.get_ami(
    most_recent=True,
    filters=[
        aws.ec2.GetAmiFilterArgs(
            name="name",
            values=["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"],
        ),
        aws.ec2.GetAmiFilterArgs(
            name="virtualization-type",
            values=["hvm"],
        )
    ],
    owners=["099720109477"] # Canonical owner ID
)

# user_data boot script installing docker
user_data_script = """#!/bin/bash
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update -y
apt-get install -y docker-ce
systemctl start docker
systemctl enable docker
"""

ec2_instance = aws.ec2.Instance("web-host",
    instance_type="t3.micro",
    ami=ubuntu_ami.id,
    subnet_id=public_subnet.id,
    vpc_security_group_ids=[ec2_sg.id],
    key_name=key_pair.key_name,
    iam_instance_profile=ec2_instance_profile.name,
    user_data=user_data_script,
    tags={"Name": "poc-ec2-instance"}
)

# ==========================================
# 7. EXPORTS & OUTPUTS
# ==========================================

pulumi.export("ec2_public_ip", ec2_instance.public_ip)
pulumi.export("ec2_url", ec2_instance.public_ip.apply(lambda ip: f"http://{ip}"))
pulumi.export("rds_endpoint", postgres_db.endpoint)
