package terraform.encryption

import rego.v1


# ---------------------------------------------------------
# SentinelPay Policy:
# Encryption at rest is mandatory for all data stores
# ---------------------------------------------------------


# Block unencrypted RDS database instances.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_db_instance"

    after := resource.change.after
    after != null

    after.storage_encrypted != true

    msg := sprintf(
        "RDS instance '%s' does not have encryption at rest enabled.",
        [resource.address],
    )
}


# Block unencrypted EBS volumes.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_ebs_volume"

    after := resource.change.after
    after != null

    after.encrypted != true

    msg := sprintf(
        "EBS volume '%s' does not have encryption at rest enabled.",
        [resource.address],
    )
}


# Block DynamoDB tables without server-side encryption enabled.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_dynamodb_table"

    after := resource.change.after
    after != null

    not dynamodb_encrypted(after)

    msg := sprintf(
        "DynamoDB table '%s' does not have server-side encryption enabled.",
        [resource.address],
    )
}


# Require an S3 bucket server-side encryption configuration.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_s3_bucket_server_side_encryption_configuration"

    after := resource.change.after
    after != null

    not s3_encryption_configured(after)

    msg := sprintf(
        "S3 encryption configuration '%s' does not define encryption at rest.",
        [resource.address],
    )
}


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

dynamodb_encrypted(config) if {
    config.server_side_encryption.enabled == true
}

s3_encryption_configured(config) if {
    count(config.rule) > 0
}
