#!/bin/bash
mkdir -p /home/ec2-user/.ssh
cat << EOF >> /home/ec2-user/.ssh/authorized_keys
{YOUR PEM HERE}
EOF
chmod 700 /home/ec2-user/.ssh
chmod 600 /home/ec2-user/.ssh/authorized_keys
chown -R ec2-user:ec2-user /home/ec2-user/.ssh
