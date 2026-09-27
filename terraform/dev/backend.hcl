# Your account ID is already filled in. Must match the bucket bootstrap/ created.
# It's the "state_bucket" output from bootstrap/.
bucket       = "terra-practice-tfstate-194169209897"
key          = "terraform/dev/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true # S3-native state locking (Terraform 1.10+)
