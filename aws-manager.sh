#!/bin/bash

# Configuration
DEFAULT_REGION=""
DEFAULT_PROFILE=""
DEFAULT_AMI=""
DEFAULT_SECURITY_GROUP=""
SPOT_SUBNET=""
ONDEMAND_SUBNET=""
USER_DATA_PATH="" # Path to your user-data.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

check_dependencies() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to describe instances
describe_instances() {
    echo "Fetching EC2 instances..."
    aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].{
            ID:InstanceId,
            Type:InstanceType,
            State:State.Name,
            IP:PublicIpAddress,
            Name:Tags[?Key==`Name`].Value | [0],
            LaunchTime:LaunchTime
        }' \
        --output table \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE
}

# Function to launch instance
launch_instance() {
    local instance_type=$1
    local spot=$2
    local name_suffix=$3

    # Determine subnet based on spot/on-demand
    local subnet_id
    if [ "$spot" = true ]; then
        subnet_id=$SPOT_SUBNET
        instance_market_options='{"MarketType":"spot","SpotOptions":{"InstanceInterruptionBehavior":"stop","SpotInstanceType":"persistent"}}'
        name_suffix="Spot-${name_suffix}"
    else
        subnet_id=$ONDEMAND_SUBNET
        instance_market_options=""
        name_suffix="OnDemand-${name_suffix}"
    fi

    echo "Launching $instance_type instance (Spot: $spot)..."
    
    local cmd="aws ec2 run-instances \
        --image-id $DEFAULT_AMI \
        --instance-type $instance_type \
        --region $DEFAULT_REGION \
        --block-device-mappings '[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeType\":\"io2\",\"VolumeSize\":1024,\"Iops\":50000}}]' \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=G6e-$name_suffix}]' \
        --user-data file://$USER_DATA_PATH \
        --security-group-ids $DEFAULT_SECURITY_GROUP \
        --subnet-id $subnet_id \
        --profile $DEFAULT_PROFILE"

    if [ "$spot" = true ]; then
        cmd="$cmd --instance-market-options '$instance_market_options'"
    fi

    eval $cmd

    if [ $? -eq 0 ]; then
        print_success "Instance launch initiated successfully!"
    else
        print_error "Failed to launch instance"
    fi
}

# Function to confirm instance operation
confirm_instance_operation() {
    local instance_id=$1
    local operation=$2

    # Get instance details
    local instance_details=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{
            ID:InstanceId,
            Type:InstanceType,
            State:State.Name,
            Name:Tags[?Key==`Name`].Value | [0]
        }' \
        --output json \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE)

    if [ $? -ne 0 ]; then
        print_error "Instance $instance_id not found"
        return 1
    fi

    local instance_name=$(echo $instance_details | jq -r '.Name')
    local instance_type=$(echo $instance_details | jq -r '.Type')
    local instance_state=$(echo $instance_details | jq -r '.State')

    print_warning "You are about to $operation instance:"
    echo "  ID: $instance_id"
    echo "  Name: $instance_name"
    echo "  Type: $instance_type"
    echo "  Current State: $instance_state"
    
    echo -n "Are you sure? (y/N): "
    read confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to terminate instances
terminate_instance() {
    local instance_id=$1
    
    if ! confirm_instance_operation "$instance_id" "terminate"; then
        print_warning "Operation cancelled"
        return
    fi

    echo "Terminating instance: $instance_id"
    aws ec2 terminate-instances \
        --instance-ids "$instance_id" \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE

    if [ $? -eq 0 ]; then
        print_success "Instance termination initiated successfully!"
    else
        print_error "Failed to terminate instance"
    fi
}

# Function to stop instances
stop_instance() {
    local instance_id=$1
    
    if ! confirm_instance_operation "$instance_id" "stop"; then
        print_warning "Operation cancelled"
        return
    fi

    echo "Stopping instance: $instance_id"
    aws ec2 stop-instances \
        --instance-ids "$instance_id" \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE

    if [ $? -eq 0 ]; then
        print_success "Instance stop initiated successfully!"
    else
        print_error "Failed to stop instance"
    fi
}

# Function to start instances
start_instance() {
    local instance_id=$1
    
    if ! confirm_instance_operation "$instance_id" "start"; then
        print_warning "Operation cancelled"
        return
    fi

    echo "Starting instance: $instance_id"
    aws ec2 start-instances \
        --instance-ids "$instance_id" \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE

    if [ $? -eq 0 ]; then
        print_success "Instance start initiated successfully!"
    else
        print_error "Failed to start instance"
    fi
}

# Function to get instance IP.
# Change the last echo line to path to your .pem file or other key.
get_instance_ip() {
    local instance_id=$1
    local instance_details=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{
            ID:InstanceId,
            IP:PublicIpAddress,
            State:State.Name,
            Name:Tags[?Key==`Name`].Value | [0]
        }' \
        --output json \
        --region $DEFAULT_REGION \
        --profile $DEFAULT_PROFILE)

    local instance_state=$(echo $instance_details | jq -r '.State')
    local ip=$(echo $instance_details | jq -r '.IP')
    local name=$(echo $instance_details | jq -r '.Name')

    if [ "$instance_state" != "running" ]; then
        print_error "Instance $instance_id is not running (Current state: $instance_state)"
        return 1
    fi

    if [ "$ip" != "null" ] && [ -n "$ip" ]; then
        print_success "Instance Details:"
        echo "  Name: $name"
        echo "  ID: $instance_id"
        echo "  IP: $ip"
        echo "  SSH command: ssh -i ~/.ssh/your-key.pem ec2-user@$ip"
    else
        print_error "No IP address found for instance $instance_id"
        return 1
    fi
}

# Main menu. Modify as you wish!
show_menu() {
    echo "AWS EC2 Instance Manager"
    echo "1. List all instances"
    echo "2. Launch g6e.xlarge (1 GPU) - On-Demand"
    echo "3. Launch g6e.xlarge (1 GPU) - Spot"
    echo "4. Launch g6e.12xlarge (4 GPU) - On-Demand"
    echo "5. Launch g6e.12xlarge (4 GPU) - Spot"
    echo "6. Stop instance"
    echo "7. Start instance"
    echo "8. Terminate instance"
    echo "9. Get instance IP"
    echo "0. Exit"
    echo -n "Select an option: "
}

# Main logic
main() {
    check_dependencies

    while true; do
        show_menu
        read choice

        case $choice in
            1)
                describe_instances
                ;;
            2)
                launch_instance "g6e.xlarge" false "1GPU"
                ;;
            3)
                launch_instance "g6e.xlarge" true "1GPU"
                ;;
            4)
                launch_instance "g6e.12xlarge" false "4GPU"
                ;;
            5)
                launch_instance "g6e.12xlarge" true "4GPU"
                ;;
            6)
                describe_instances
                echo -n "Enter instance ID to stop: "
                read instance_id
                stop_instance "$instance_id"
                ;;
            7)
                describe_instances
                echo -n "Enter instance ID to start: "
                read instance_id
                start_instance "$instance_id"
                ;;
            8)
                describe_instances
                echo -n "Enter instance ID to terminate: "
                read instance_id
                terminate_instance "$instance_id"
                ;;
            9)
                describe_instances
                echo -n "Enter instance ID: "
                read instance_id
                get_instance_ip "$instance_id"
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo
    done
}

main "$@"