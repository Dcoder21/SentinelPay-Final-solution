package terraform.s3

import rego.v1


# ---------------------------------------------------------
# SentinelPay Policy:
# S3 buckets must not be publicly accessible
# ---------------------------------------------------------


# Block S3 buckets configured with a public ACL.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_s3_bucket"

    after := resource.change.after
    after != null

    public_acl(after.acl)

    msg := sprintf(
        "S3 bucket '%s' uses a public ACL. SentinelPay S3 buckets must not be public.",
        [resource.address],
    )
}


# Block insecure S3 Public Access Block configuration.
deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_s3_bucket_public_access_block"

    after := resource.change.after
    after != null

    not secure_public_access_block(after)

    msg := sprintf(
        "S3 public access block '%s' does not block all forms of public access.",
        [resource.address],
    )
}


# ---------------------------------------------------------
# Helper: identify public ACL values
# ---------------------------------------------------------

public_acl(acl) if {
    acl == "public-read"
}

public_acl(acl) if {
    acl == "public-read-write"
}

public_acl(acl) if {
    acl == "authenticated-read"
}


# ---------------------------------------------------------
# Helper: require all four AWS S3 public-access protections
# ---------------------------------------------------------

secure_public_access_block(config) if {
    config.block_public_acls == true
    config.ignore_public_acls == true
    config.block_public_policy == true
    config.restrict_public_buckets == true
}
