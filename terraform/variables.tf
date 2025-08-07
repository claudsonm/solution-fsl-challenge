# In this file put the variables related to the deployment
variable "environment" {
    type = string
    description = "The environment name"
    validation {
        condition = contains(["devel", "stage", "prod"], var.environment)
        error_message = "The environment name must be one of: devel, stage or prod."
    }
}
