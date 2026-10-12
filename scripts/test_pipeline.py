"""Check the deployment dependency graph and fail-closed OPA behaviour."""
import json
from pathlib import Path
import subprocess

import yaml

workflow = yaml.safe_load(Path('.github/workflows/ci.yml').read_text())
jobs = workflow['jobs']
deploy = jobs['deploy-infrastructure']
assert set(deploy['needs']) == set(jobs) - {'deploy-infrastructure'}
assert "github.event_name == 'push'" in deploy['if']
assert "github.ref == 'refs/heads/main'" in deploy['if']
assert "github.repository == 'Dcoder21/SentinelPay-Final-solution'" in deploy['if']
assert 'always()' not in deploy['if']
assert deploy['concurrency']['cancel-in-progress'] is False
assert workflow['permissions'] == {'contents': 'read'}
assert deploy['permissions']['id-token'] == 'write'
steps = deploy['steps']
commands = [s.get('run', '') for s in steps]
opa = next(i for i, c in enumerate(commands) if 'conftest test infra/environments/dev/plan.json' in c)
apply = next(i for i, c in enumerate(commands) if 'terraform apply ' in c)
assert opa < apply
assert commands[apply].strip() == 'terraform apply -input=false -lock-timeout=5m tfplan'
assert not steps[opa].get('continue-on-error')
assert not steps[apply].get('if')
assert not steps[apply].get('continue-on-error')
assert not any('upload-artifact' in s.get('uses', '') for s in steps)

def policy_result(value):
    result = subprocess.run(
        ['conftest', 'test', '-', '--policy', 'policy/terraform', '--all-namespaces', '--output', 'json'],
        input=json.dumps(value), text=True, capture_output=True,
    )
    assert result.returncode in (0, 1), result.stderr
    parsed = json.loads(result.stdout)
    return sum(len(item.get('failures', [])) for item in parsed)

for family in ['encryption', 'iam', 'network', 's3']:
    for case in ['secure', 'insecure']:
        value = json.loads(Path(f'policy-tests/{family}/{case}.json').read_text())
        failures = policy_result(value)
        assert (failures == 0) == (case == 'secure'), (family, case, failures)

# Modern AWS rule types and JSON-string IAM policies must be checked too.
assert policy_result({'resource_changes': [{
    'address': 'module.compute.aws_vpc_security_group_ingress_rule.ssh',
    'type': 'aws_vpc_security_group_ingress_rule',
    'change': {'after': {'cidr_ipv4': '0.0.0.0/0', 'from_port': 22, 'to_port': 22, 'ip_protocol': 'tcp'}},
}]}) > 0
assert policy_result({'resource_changes': [{
    'address': 'aws_iam_role_policy.admin', 'type': 'aws_iam_role_policy',
    'change': {'after': {'policy': json.dumps({'Statement': [{'Effect': 'Allow', 'Action': '*', 'Resource': '*'}]})}},
}]}) > 0

# Public ports are forbidden even when the address resembles the old ALB rule.
for port in (80,443):
    assert policy_result({'resource_changes': [{
        'address': 'module.edge.aws_vpc_security_group_ingress_rule.https',
        'type': 'aws_vpc_security_group_ingress_rule',
        'change': {'after': {'cidr_ipv4': '0.0.0.0/0', 'from_port': port, 'to_port': port, 'ip_protocol': 'tcp'}},
    }]}) > 0
image_steps = jobs['trivy-images']['steps']
image_commands = [s.get('run','') for s in image_steps]
scan_gate = next(i for i,c in enumerate(image_commands) if 'HIGH or CRITICAL vulnerabilities' in c)
integration = next(i for i,c in enumerate(image_commands) if 'python scripts/test_images.py' in c)
package = next(i for i,c in enumerate(image_commands) if 'docker save ' in c)
assert scan_gate < integration < package
assert any('download-artifact' in s.get('uses','') and s['with']['name'] == 'scanned-application-images' for s in steps)
print('Deployment dependencies, scanned image ordering, and 12 positive/negative OPA cases passed.')
