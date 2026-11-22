"""DynamoDB access: tokens, rate limits and the visitor log."""

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


def save_token(token_hash: str, email: str, expires_at: int) -> None:
    _table(settings().tokens_table).put_item(
        Item={"token_hash": token_hash, "email": email, "expires_at": expires_at},
        ConditionExpression="attribute_not_exists(token_hash)",
    )


def consume_token(token_hash: str, now: int) -> str | None:
    """Delete the token if it exists and hasn't expired, returning its email address.

    The conditional delete makes each link single-use even if it is opened twice at once.
    DynamoDB's TTL deletes expired items only eventually, so expiry is checked here too.
    """
    try:
        result = _table(settings().tokens_table).delete_item(
            Key={"token_hash": token_hash},
            ConditionExpression="attribute_exists(token_hash) AND expires_at > :now",
            ExpressionAttributeValues={":now": now},
            ReturnValues="ALL_OLD",
        )
    except ClientError as error:
        if _is_conditional_failure(error):
            return None
        raise
    return str(result["Attributes"]["email"])


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
