"""DynamoDB access: sign-in codes, rate limits and the visitor log."""

import hmac
from datetime import UTC, datetime
from functools import cache
from typing import TYPE_CHECKING

import boto3
from botocore.exceptions import ClientError

from auth.config import required, settings

# Type stubs are dev-only; they aren't in the Lambda package.
if TYPE_CHECKING:
    from mypy_boto3_dynamodb.service_resource import Table


@cache
def _table(name: str) -> "Table":
    return boto3.resource("dynamodb").Table(name)


def _is_conditional_failure(error: ClientError) -> bool:
    return error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException"


def allow(key: str, limit: int, window_seconds: int, now: int) -> bool:
    """Fixed-window counter. Atomically counts this attempt unless the limit is reached."""
    table_name = required(settings().rate_limits_table, "RATE_LIMITS_TABLE")
    window_start = now - now % window_seconds
    try:
        _table(table_name).update_item(
            Key={"key": f"{key}#{window_start}"},
            UpdateExpression="ADD attempts :one SET expires_at = :expires",
            ConditionExpression="attribute_not_exists(attempts) OR attempts < :limit",
            ExpressionAttributeValues={
                ":one": 1,
                ":limit": limit,
                ":expires": window_start + window_seconds,
            },
        )
    except ClientError as error:
        if _is_conditional_failure(error):
            return False
        raise
    return True


def save_code(email: str, code_hash: str, expires_at: int) -> None:
    """Store a new code, replacing any earlier one for this address and its attempts.

    Replacing resets the attempt count, but new codes are themselves rate-limited per
    address, which caps the guesses an attacker gets per hour.
    """
    _table(settings().codes_table).put_item(
        Item={"email": email, "code_hash": code_hash, "attempts": 0, "expires_at": expires_at},
    )


def use_code(email: str, code_hash: str, now: int, max_attempts: int) -> bool:
    """True, exactly once, if `code_hash` matches the live code for `email`.

    The attempt is counted before the comparison, in one conditional update, so parallel
    guesses can't exceed the limit. A match is then deleted conditionally, so two
    simultaneous correct submissions can't both succeed. DynamoDB's TTL deletes expired
    items only eventually, so expiry is checked here too.
    """
    table = _table(settings().codes_table)
    try:
        item = table.update_item(
            Key={"email": email},
            UpdateExpression="ADD attempts :one",
            ConditionExpression="expires_at > :now AND attempts < :max",
            ExpressionAttributeValues={":one": 1, ":now": now, ":max": max_attempts},
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except ClientError as error:
        if _is_conditional_failure(error):
            return False
        raise

    if not hmac.compare_digest(str(item["code_hash"]), code_hash):
        return False

    try:
        table.delete_item(
            Key={"email": email},
            ConditionExpression="code_hash = :hash",
            ExpressionAttributeValues={":hash": code_hash},
        )
    except ClientError as error:
        if _is_conditional_failure(error):
            return False
        raise
    return True


def record_visit(email: str, now: int) -> None:
    table_name = required(settings().visitors_table, "VISITORS_TABLE")
    timestamp = datetime.fromtimestamp(now, UTC).isoformat()
    _table(table_name).update_item(
        Key={"email": email},
        UpdateExpression=(
            "SET first_seen = if_not_exists(first_seen, :now), last_seen = :now ADD sign_ins :one"
        ),
        ExpressionAttributeValues={":now": timestamp, ":one": 1},
    )
