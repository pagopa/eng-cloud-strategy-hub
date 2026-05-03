resource "null_resource" "example" {}

module "example" {
  source = "./missing"
}
