# Everything that differs between environments lives here.
# To make prod: copy live/dev to live/prod and change these values.
locals {
  env    = "dev"
  region = "us-west-2"
}
