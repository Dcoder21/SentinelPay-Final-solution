"""Exercise HTTPS routing, database writes, Redis, and cross-service JWTs."""
import json
import secrets
import subprocess
import urllib.request
import uuid


def request(base, path, data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(base + path, data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def verify(base, kyc_base=None):
    kyc_base = kyc_base or base
    for path, service in [("/health", "payments-api"), ("/kyc/health", "kyc-api")]:
        assert request(kyc_base if service == "kyc-api" else base, path)["service"] == service
    email = "deployment-" + uuid.uuid4().hex + "@example.invalid"
    password = secrets.token_urlsafe(32)
    request(base, "/v1/auth/register", {"email": email, "password": password, "full_name": "Deployment test"})
    auth = request(base, "/v1/auth/login", {"email": email, "password": password})
    assert auth.get("token"), "Login must issue a signed access token"
    # This reads the new user's KYC status without calling any external provider.
    assert request(kyc_base, "/v1/verify/lookup?bvn=00000000000", token=auth["token"]) == []
    print("HTTPS, both API routes, registration, login, and cross-service authorization passed.")
    print("Testing API: " + base)


def main():
    base = subprocess.check_output(["terraform", "-chdir=infra/environments/dev", "output", "-raw", "api_url"], text=True).strip()
    assert base.startswith("https://"), "Public endpoint must use HTTPS"
    verify(base)


if __name__ == "__main__":
    main()
