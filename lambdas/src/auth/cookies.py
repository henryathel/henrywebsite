"""CloudFront signed cookies granting read access to /roles/*."""

import base64
import json
from functools import cache

import boto3
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from mypy_boto3_ssm import SSMClient

from auth.config import required, settings


@cache
def _ssm() -> SSMClient:
    return boto3.client("ssm")


@cache
def _private_key() -> rsa.RSAPrivateKey:
    """Fetched once per container. The key never appears in Terraform state or env vars."""
    name = required(settings().signing_key_parameter, "SIGNING_KEY_PARAMETER")
    pem = _ssm().get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    key = serialization.load_pem_private_key(pem.encode(), password=None)
    if not isinstance(key, rsa.RSAPrivateKey):
        raise TypeError("cookie signing key must be RSA")
    return key


def _cloudfront_b64(data: bytes) -> str:
    # CloudFront's URL-safe variant of base64.
    return base64.b64encode(data).decode().translate(str.maketrans("+=/", "-_~"))


def signed_cookies(resource: str, expires_at: int, path: str) -> list[str]:
    """Set-Cookie values for a custom policy allowing `resource` until `expires_at`."""
    config = settings()
    key_pair_id = required(config.key_pair_id, "KEY_PAIR_ID")
    max_age = required(config.cookie_ttl_seconds, "COOKIE_TTL_SECONDS")

    policy = json.dumps(
        {
            "Statement": [
                {"Resource": resource, "Condition": {"DateLessThan": {"AWS:EpochTime": expires_at}}}
            ]
        },
        separators=(",", ":"),
    ).encode()
    # CloudFront verifies RSA signatures over SHA-1; it doesn't accept another digest.
    signature = _private_key().sign(policy, padding.PKCS1v15(), hashes.SHA1())  # noqa: S303

    attributes = f"Path={path}; Max-Age={max_age}; Secure; HttpOnly; SameSite=Lax"
    return [
        f"CloudFront-Policy={_cloudfront_b64(policy)}; {attributes}",
        f"CloudFront-Signature={_cloudfront_b64(signature)}; {attributes}",
        f"CloudFront-Key-Pair-Id={key_pair_id}; {attributes}",
    ]
