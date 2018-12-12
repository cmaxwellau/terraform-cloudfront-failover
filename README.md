# Terraform Cloudfront Failover
This is an example script that demonmstrates how to failover a Cloudfront-based website built with terraform, to a specific S3 bucket for site maintenance purposes.



# Install / Setup
## Install cli dependencies
* aws cli
* jq

## Configure AWS credentials in your environment
You can set a default region in the CLI environment. This can still be overriden by an explicit command line option.

```
$ export AWS_REGION=ap-southeast-2
```

Configure AWS credentials using a profile in ~/.aws/credentials and refer to it through an environment variable:

```
$ export AWS_PROFILE=my-dev-account-profile
```

You can also configure explicit credentials using environment variables:

```
$ export AWS_ACCESS_KEY_ID=AKIA12345678ABCDEAFGH
$ export AWS_SECRET_ACCESS_KEY=12345678ABCDEFGHabcdefgh12345678abcdefgh
```

## Deploy S3 websites
The example main and failover S3 websites are included and can be provisioned with 
```
terraform init
terraform apply
```

# Usage
## Failover using terraform test environment
The script can identify resources built by terraform using the terraform state file

```
failover.sh -f terraform.tfstate
```

## Failover with manual settings
```
failover.sh -c E1M6O00B4YABCD -u https://d1593sj4rabcde.cloudfront.net/ -i E3OWF71234ABCD -f failover-website20181206082214035709999999.s3.ap-southeast-2.amazonaws.com
```
