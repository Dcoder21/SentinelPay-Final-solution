import boto3
import json
import os

ec2 = boto3.client("ec2")

QUARANTINE_SG = os.environ["QUARANTINE_SG"]


def collect_network_interfaces(value):
    interfaces = []

    if isinstance(value, dict):
        for key, item in value.items():
            if key == "networkInterfaceId" and isinstance(item, str):
                interfaces.append(item)

            interfaces.extend(
                collect_network_interfaces(item)
            )

    elif isinstance(value, list):
        for item in value:
            interfaces.extend(
                collect_network_interfaces(item)
            )

    return interfaces


def lambda_handler(event, context):
    print(json.dumps(event))

    finding = event.get("detail", {})

    severity = float(
        finding.get("severity", 0)
    )

    if severity < 7:
        return {
            "status": "ignored",
            "reason": "severity below threshold"
        }

    interfaces = list(
        set(
            collect_network_interfaces(finding)
        )
    )

    quarantined = []

    for eni in interfaces:
        ec2.modify_network_interface_attribute(
            NetworkInterfaceId=eni,
            Groups=[
                QUARANTINE_SG
            ]
        )

        quarantined.append(eni)

    return {
        "status": "processed",
        "quarantined_interfaces": quarantined
    }