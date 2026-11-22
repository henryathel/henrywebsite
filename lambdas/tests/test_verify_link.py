import base64
import json
import time
from typing import Any

import boto3
import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from auth import verify_link
from auth.store import save_token
from auth.tokens import new_token, token_hash
from tests.conftest import SITE, event

pytestmark = pytest.mark.usefixtures("aws")


def issue(email: str = "visitor@example.com", ttl: int = 1800) -> str:
    token = new_token()
    save_token(token_hash(token), email, int(time.time()) + ttl)
    return token


def post(token: str) -> dict[str, Any]:
    return verify_link.handler(event("POST", "/api/auth/verify", body=f"token={token}"), None)


def cookie_values(response: dict[str, Any]) -> dict[str, str]:
    pairs = (cookie.split(";", 1)[0].split("=", 1) for cookie in response["cookies"])
    return {name: value for name, value in pairs}


def from_cloudfront_b64(value: str) -> bytes:
    return base64.b64decode(value.translate(str.maketrans("-_~", "+=/")))


def test_get_shows_confirmation_without_using_the_token() -> None:
    token = issue()
    response = verify_link.handler(event("GET", "/api/auth/verify", query={"token": token}), None)
    assert response["statusCode"] == 200
    assert f'value="{token}"' in response["body"]
    assert response["headers"]["Cache-Control"] == "no-store"
    assert boto3.resource("dynamodb").Table("tokens").scan()["Count"] == 1


def test_get_with_malformed_token_redirects() -> None:
    response = verify_link.handler(
        event("GET", "/api/auth/verify", query={"token": "<script>"}), None
    )
    assert response["headers"]["Location"] == "/login.html?expired=1"


def test_post_signs_in_once(signing_key: rsa.RSAPrivateKey) -> None:
    token = issue()
    response = post(token)

    assert response["statusCode"] == 303
    assert response["headers"]["Location"] == "/roles/"
    for cookie in response["cookies"]:
        assert "Path=/roles/" in cookie
        assert "Max-Age=432000" in cookie
        assert "Secure" in cookie and "HttpOnly" in cookie and "SameSite=Lax" in cookie

    values = cookie_values(response)
    assert values["CloudFront-Key-Pair-Id"] == "K2TESTKEYPAIR"
    policy = from_cloudfront_b64(values["CloudFront-Policy"])
    statement = json.loads(policy)["Statement"][0]
    assert statement["Resource"] == f"{SITE}/roles/*"
    expires = statement["Condition"]["DateLessThan"]["AWS:EpochTime"]
    assert abs(expires - (time.time() + 432000)) < 5

    signing_key.public_key().verify(
        from_cloudfront_b64(values["CloudFront-Signature"]),
        policy,
        padding.PKCS1v15(),
        hashes.SHA1(),
    )

    [visitor] = boto3.resource("dynamodb").Table("visitors").scan()["Items"]
    assert visitor["email"] == "visitor@example.com"
    assert visitor["sign_ins"] == 1

    assert post(token)["headers"]["Location"] == "/login.html?expired=1"


def test_expired_token_is_refused() -> None:
    token = issue(ttl=-1)
    assert post(token)["headers"]["Location"] == "/login.html?expired=1"
    assert boto3.resource("dynamodb").Table("visitors").scan()["Count"] == 0


def test_unknown_token_is_refused() -> None:
    assert post(new_token())["headers"]["Location"] == "/login.html?expired=1"


def test_repeat_visitor_is_counted() -> None:
    post(issue())
    post(issue())
    [visitor] = boto3.resource("dynamodb").Table("visitors").scan()["Items"]
    assert visitor["sign_ins"] == 2
    assert str(visitor["first_seen"]) <= str(visitor["last_seen"])


def test_requests_that_bypass_cloudfront_are_refused() -> None:
    token = issue()
    response = verify_link.handler(
        event("POST", "/api/auth/verify", body=f"token={token}", secret="x" * 40), None
    )
    assert response["statusCode"] == 403
    assert boto3.resource("dynamodb").Table("tokens").scan()["Count"] == 1
