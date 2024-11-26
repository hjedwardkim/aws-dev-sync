# AWS Dev Sync

A streamlined development workflow that enables local development with automatic syncing to cloud VMs. Perfect for ML/AI developers working with GPU instances. 

## Features

🔄 Bidirectional syncing between local and cloud environments
📝 Local development with VS Code
🚀 Automatic file watching and syncing
📊 Log management and retrieval
🛠️ Compatible with macOS (local) and Linux (remote)

## Prerequisites

*This tool assumes you have the required permissions and role on AWS.*

Please ensure you have installed the following (e.g. with brew)
- fswatch
- rsync
- awscli v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Remote SSH (VS Code extension)

## Set-up Guide

1. Install dependencies and ensure AWS is configured.
2. Configure your SSH (`~/.ssh/config`)
```
Host your-vm-ip
  HostName your-vm-ip
  IdentityFile ~/.ssh/your-key.pem
  User ec2-user
```
NB: `user-data.sh` is used in the instance manager script `aws-manager.sh`. Consult AWS documentation for setting up your user-data if you haven't already. The one you will find here is an example template.
3. Set the following in the scripts below:
- `aws-manager.sh` is a convenience script you can use to describe/start/stop/terminate instances.
    - Configure the first few lines with your relevant AWS info:
        - `DEFAULT_REGION`
        - `DEFAULT_PROFILE`
        - `DEFAULT_AMI`
        - `DEFAULT_SECURITY_GROUP`
        - `SPOT_SUBNET`
        - `ONDEMAND_SUBNET`
        - `USER_DATA_PATH`
    - Note that you may want to configure the `block-device-mappings` parameter to your preference.
    - L238 ssh path should point to your key.
    - The script currently contains options for g6e.xlarge and g6e.12xlarge instances in both on-demand and spot versions. You can configure these to something else.
- `vm_sync.sh` is an rsync/fswatch-based script that persistently checks (once initialized) for any changes in the working local directory (`LOCAL_DIR`). After a 1 second delay, any file changes will sync to your VM. Any changes in the `LOG_DIR` state in your remote instance will sync to your local machine.
    - Replace `REMOTE_HOST` with your VM's IP
    - Adjust the working directories as needed (e.g. to the root of your repo.)
    - Adjust the `LOG_DIR` as needed (where you want the outputs of your repo to be stored and synced.)
    - You can add any exclusionary patterns in `sync_to_vm()` to prevent sync.
4. Run `chmod +x` to all `.sh` files.

## Workflow

1. Open your favorite terminal emulator, run `aws-manager.sh`. Start an instance of your choosing. Get the IP of the initialized VM.
2. SSH into the VM with VS Code's Remote SSH extension.
3. Run `vm_sync.sh` from your terminal to begin sync.
4. Develop locally. Your changes will sync automatically to your VM's working directory from `LOCAL_DIR` to `REMOTE_DIR` set in `vm_sync.sh`.
5. Test/run your code remotely (e.g. ML training runs with your GPU VM). Outputs stored in `LOG_DIR` will automatically sync back to your local machine's working directory.
