"""Run a service's tests with disposable JWT keys and an in-memory limiter."""
import os
import secrets
from pathlib import Path
import subprocess
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

service = sys.argv[1]
if service not in ('payments-api', 'kyc-api'):
    raise SystemExit('Expected payments-api or kyc-api')

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
test_env = os.environ.copy()
test_env['JWT_PUBLIC_KEY'] = key.public_key().public_bytes(
    serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()
if service == 'payments-api':
    test_env['JWT_PRIVATE_KEY'] = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
test_env['RATELIMIT_STORAGE_URI'] = 'memory://'
test_env['RATE_LIMIT_KEY_SECRET'] = secrets.token_urlsafe(32)
test_env['SESSION_SIGNING_KEY'] = secrets.token_urlsafe(32)

# Keys exist only in this test process tree; no production secrets are needed.
service_path = Path(__file__).resolve().parents[1] / 'Amdari-Project--02' / 'services' / service
raise SystemExit(subprocess.run(
    [sys.executable, '-m', 'pytest', 'tests', '-q'], cwd=service_path, env=test_env,
).returncode)
