# Test 3 - External Volumes and Stateful Applications

## Synopsis
Stateful applications require some extra care and attention in Kubernetes through the StatefulSet object, which gives some better configuration for items that need to maintain state via external volumes such as databases by providing sticky identities. ECS insinuates that this is built into ECS by mounting an EBS or EFS volume.

In this test, I will be leveraging the walkthrough provided [here](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html)and creating an nginx web server on ECS and EKS (both running on Fargate this time) and serving a standard web file each that is hosted on EFS. As the tasks / pods are then terminated, we will be able to confirm that new tasks are pulling information from the EFS share accordingly.

## Why bother with stateful applications?
Due to the nature of containerised applications, it may be necessary to persist state, either because you're running an application like a web page that need access to local storage or you could be running a containerised database like MongoDB for dev and testing purposes. Either way, with the continued demand of technologies like Kubernetes, there will continue to be a use case for persistent storage that is easily accessible by a container in order to provide fast, local storage that can persist container failures.

Within Fargate, the primary way of providing state to containers is by using AWS EFS. ECS and EKS instances hosted on EC2 can also utilise EBS as well, as you would manage on an on-prem cluster. 

## ECS

### DNS Names for EFS Volumes
When working with EFS volumes, an important thing to note is the EFS file by default creates a private DNS name for instances to connect to, this can be allowed within your VPC by setting the DNS hostnames value to true, such as in the below:

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}
```

### Creating the EFS Share
Creating the share itself is relatively straight forward, the 3 main components that are needed are the file system itself, an access point, which allows AWS applications to access the file share (i.e. our ECS containers) and a mount target which allows you to access the file share from within your VPC.

```hcl
resource "aws_efs_file_system" "ecs" {
	creation_token = "ecs-files"
}

resource "aws_efs_access_point" "ecs-access" {
	file_system_id = aws_efs_file_system.ecs.id
}
  
resource "aws_efs_mount_target" "ecs" {
	file_system_id = aws_efs_file_system.ecs.id
	subnet_id = aws_subnet.main-1.id
	security_groups = [aws_security_group.efs.id]
}
```

There are two main considerations for this project:
1. The mount target does require a security group allowing access from port 2049, which is the typical NFS port within AWS
2. There must be a mount target in each subnet that needs to access the file system, here I have just used one subnet for the ECS portion of the test 

### The container is on Fargate... So what's with the EC2?
In short, the EC2 is needed to create and send the `index.html` file over to EFS so that it can be proved that the container is able to display files that it itself did not create.

It does this using a super simple userdata script that creates a folder, mounts the EFS share to that folder and creates an index.html with a line of text to display to the user.

```bash
#!/bin/bash
mkdir efs
mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.ecs.dns_name}:/ efs

echo "Hello World, I come from EFS!" > efs/index.html
```

### Creating ECS clusters on fargate
Creating an ECS cluster on Fargate has some slightly different considerations to creating on EC2.

Firstly, your task definition requires an execution role with the policy `AmazonECSTaskExecutionRolePolicy` attached which allows ECS and Fargate to make the necessary API calls to AWS services.

Secondly, when creating your ECS Service, you must specify the `launch_type` as `"FARGATE"` which will tell ECS to provision the Fargate compute in line with the specs listed on the task definition, which leads us to...

### Understanding the task definition - Making it work on Fargate
This is where the bulk of the Fargate configuration happens.

Firstly, the `network_mode` is set as `"awsvpc"` which associates an Elastic Network Interface with the task to allow it to operate within your VPC (by assigning a subnet within your service).

You then need to assign your CPU and Memory values, as such:

```hcl
resource "aws_ecs_task_definition" "ecs-task" {
	cpu = 256
	memory = 1024
}
```

Depending on the image that you are running, you may need to specify the `requires_compatiblities = ["FARGATE"]` option to ensure that the task definition will work with Fargate accordingly.

### Understanding the task definition - Connecting the EFS file system
There are a couple of things needed here to make the Task definition work accordingly:

1. A Task Role needs to be created that has the following policy document generated and attached:

```hcl
data "aws_iam_policy_document" "ecs-efs" {
	statement {
		actions = [
			"elasticfilesystem:ClientMount",
			"elasticfilesystem:ClientWrite"
		]

		resources = [aws_efs_file_system.ecs.arn]
	
		condition {
			test = "StringEquals"
			variable = "elasticfilesystem:AccessPointArn"
	
			values = [aws_efs_access_point.ecs-access.arn]
		}
	}
}
```

2. In the container definition, a mount point needs to be defined as following:

```json
[
	{
		"name": "test",
		"image": "nginx",
		"mountPoints": [
			{
				"containerPath": "/usr/share/nginx/html",
				"sourceVolume": "ecs-file"
			}
		]
	}
]
```

3. In your task definition resource, the volume must be configured to find and access your EFS file accordingly:

```hcl
resource "aws_ecs_task_definition" "task" {
	...
	volume {
		name = "ecs-file"

		efs_volume_configuration {
			file_system_id = aws_efs_file_system.main.id
			transit_encryption = "ENABLED"
			authorization_config {
				access_point_id = aws_efs_access_point.main.id
				iam = "ENABLED"
			}
		}
	}
}
```

Once this is all completed and run your nginx server should be displaying your generated file on EFS!

## EKS

### Getting your Fargate compute set up
Fargate on EKS works slightly differently, in that you need to configure a Fargate Profile within your cluster and this requires access to *2 private* subnets, so that means every student's worst nightmare for billing: NAT Gateways!

```hcl
resource "aws_eks_fargate_profile" "main" {
	cluster_name = aws_eks_cluster.main.name
	fargate_profile_name = "test-3"

	pod_execution_role_arn = aws_iam_role.eks-fargate.arn
	subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]

	selector {
		namespace = "default"
	}
}
```

Also be sure to choose the namespace selector to match the namespace that you are deploying your YAML files to, otherwise it won't work!

Lastly, as usual, you'll need a couple of IAM policies, so for your Fargate profile, you'll need a role that has the `AmazonEKSFargatePodExecutionRolePolicy` attached, and the `AmazonEKSClusterPolicy` attached to your cluster.

### EFS
The EFS setup is pretty much the same as our ECS example, except we need to make sure to configure mount points for ALL subnets that will be used by the EKS cluster and EC2.

### The Kubes files
The Kubernetes files need to be deployed in a very specific order:
#### 1. CSIDriver and Storage Class
This can be done in one file and just contains the drivers and provisioner location necessary for EKS to find and manage the EFS file share accordingly:

```yaml
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: efs.csi.aws.com
spec:
  attachRequired: false
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
```

#### 2. Volume
We can then configure the Volume within Kubernetes with our `PersistentVolume` file, this tells EFS what file system we want to access via the `volumeHandle` and what permissions we want to assign at a cluster level:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-volume
spec:
  capacity:
	storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: <volume-name>
    volumeAttributes:
	  encryptInTransit: "true"
```

It's worth noting that whilst we are provisioning a storage capacity here, as EFS is an elastic storage system, this field is ignored in practice, but is needed for the Volume to run correctly.

the `volumeHandle` is your Volume ID of the EFS, and can be set as an output from Terraform or can be received via the CLI running the following command:

```bash
aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text --profile <profile-name>
```

#### 3. Volume Claim
The Volume Claim is mostly a repeat of the Volume file and confirms the pod specific requirements for that Volume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim
spec:
  resources:
    requests:
      storage: 10Gi
  storageClassName: efs-sc
  accessModes:
    - ReadWriteMany
```

#### 4. Deployment
The main change in the deployment file is again just refering the volume details within the spec, as follows:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
...
  spec:
    containers:
    ...
      volumeMounts:
        - name: efs
          mountPath: /usr/share/nginx/html
    volumes:
      - name: efs
        persistentVolumeClaim:
          claimName: efs-claim
```

The `volumeMounts` section defines where the volume will be mounted within the pod, and the `volumes` section just refers to the PVC that we've defined previously.

### Testing it worked
As the Fargate cluster is included into a private subnet, it's not as easy to get access to your Nginx containers, and this is something I'll be covering in Test 4, however, we can get around this to prove that the file share was mounted correctly by running the following commands:
```bash
kubectl exec -it <pod-name> -- bin/bash
cd /usr/share/nginx/html
cat index.html
```

And we should get returned the text that we created using our EC2!

## Wrapping Up
EFS can be a powerful tool to help enable stateful applications within your containerised workloads, and so being able to understand the basics as to how to make this work on ECS and EKS is vital to extending the capabilities of your containers and accessing new ways to manage them going forward.

---
## Resources
- https://aws.amazon.com/blogs/containers/developers-guide-to-using-amazon-efs-with-amazon-ecs-and-aws-fargate-part-1/
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tutorial-efs-volumes.html
- https://apeksh742.medium.com/mounting-efs-on-aws-instance-using-terraform-fc359ae6d0be
- https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/run-stateful-workloads-with-persistent-data-storage-by-using-amazon-efs-on-amazon-eks-with-aws-fargate.html
