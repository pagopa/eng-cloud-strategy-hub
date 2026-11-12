import json
import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterator

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)
NAMESPACE = "AWSBackup/Coverage"
SUPPORTED_TYPES = frozenset({"DynamoDB", "S3"})


@dataclass(frozen=True)
class Policy:
    max_backup_age_seconds: int
    freshness_tolerance_seconds: int
    initial_grace_seconds: int
    reminder_interval_seconds: int

    def __post_init__(self):
        values = (
            self.max_backup_age_seconds, self.freshness_tolerance_seconds,
            self.initial_grace_seconds, self.reminder_interval_seconds,
        )
        if any(type(value) is not int for value in values):
            raise ValueError("Coverage thresholds must be whole seconds")
        if (
            self.max_backup_age_seconds <= 0
            or not 0 <= self.freshness_tolerance_seconds < self.max_backup_age_seconds
            or self.initial_grace_seconds < 0
            or self.reminder_interval_seconds <= 0
        ):
            raise ValueError("Invalid coverage freshness, grace, or reminder policy")


def validate_configuration(tags: dict[str, str], types: set[str], policy: Policy):
    if not tags or any(not key.strip() or not value.strip() for key, value in tags.items()):
        raise ValueError("Expected resource tags must contain non-empty keys and values")
    if not types or not types <= SUPPORTED_TYPES:
        raise ValueError("Coverage supports only DynamoDB tables and S3 general purpose buckets")
    if not isinstance(policy, Policy):
        raise ValueError("An explicit coverage policy is required")


def pages(operation, request_token: str, response_token: str, **parameters) -> Iterator[dict]:
    seen = set()
    while True:
        response = operation(**parameters)
        yield response
        token = response.get(response_token)
        if not token:
            break
        encoded = json.dumps(token, sort_keys=True)
        if encoded in seen:
            raise RuntimeError(f"Repeated pagination token in {operation}")
        seen.add(encoded)
        parameters[request_token] = token


def latest_snapshot(points: list[dict], region: str, account: str) -> int | None:
    latest = None
    for point in points:
        if point["Status"] not in {"COMPLETED", "PARTIAL", "DELETING", "EXPIRED", "AVAILABLE", "STOPPED", "CREATING"}:
            raise ValueError("Unrecognized recovery point status")
        if point["Status"] != "COMPLETED":
            continue
        parts = point["RecoveryPointArn"].split(":", 5)
        if len(parts) != 6 or parts[0] != "arn":
            raise ValueError("Unrecognized recovery point ARN")
        _, _, service, point_region, point_account, identifier = parts
        if point_region != region or point_account != account:
            continue
        if service == "backup" and identifier.startswith("recovery-point:"):
            if identifier.removeprefix("recovery-point:").lower().startswith("continuous"):
                continue
        elif not (service == "dynamodb" and identifier.startswith("table/") and "/backup/" in identifier):
            raise ValueError("Unsupported snapshot recovery point ARN shape")
        created = point.get("CreationDate")
        if not isinstance(created, datetime) or created.tzinfo is None:
            raise ValueError("Recovery point CreationDate must be a timezone-aware timestamp")
        timestamp = int(created.timestamp())
        latest = timestamp if latest is None else max(latest, timestamp)
    return latest


class DynamoState:
    def __init__(self, client, table_name: str):
        self.client = client
        self.table_name = table_name

    def load(self) -> dict[str, dict]:
        records = {}
        for page in pages(
            self.client.scan, "ExclusiveStartKey", "LastEvaluatedKey",
            TableName=self.table_name, ConsistentRead=True,
        ):
            for item in page["Items"]:
                records[item["resource_arn"]["S"]] = json.loads(item["payload"]["S"])
        return records

    def save(self, arn: str, item: dict, previous: dict | None):
        parameters = {
            "TableName": self.table_name,
            "Item": {
                "resource_arn": {"S": arn},
                "payload": {"S": json.dumps(item, sort_keys=True)},
            },
            "ConditionExpression": "attribute_not_exists(resource_arn)",
        }
        if previous is not None:
            parameters.update(
                ConditionExpression="#payload = :previous",
                ExpressionAttributeNames={"#payload": "payload"},
                ExpressionAttributeValues={
                    ":previous": {"S": json.dumps(previous, sort_keys=True)}
                },
            )
        self.client.put_item(**parameters)


class Scanner:
    def __init__(
        self, s3, dynamodb, backup, sns, metrics, state, region: str,
        account: str, partition: str, expected_tags: dict[str, str],
        resource_types: set[str], policy: Policy, topic_arn: str, name: str,
    ):
        validate_configuration(expected_tags, resource_types, policy)
        self.s3 = s3
        self.dynamodb = dynamodb
        self.backup = backup
        self.sns = sns
        self.metrics = metrics
        self.state = state
        self.region = region
        self.account = account
        self.partition = partition
        self.expected_tags = expected_tags
        self.resource_types = resource_types
        self.policy = policy
        self.topic_arn = topic_arn
        self.name = name

    def metric(self, name: str, value: int):
        self.metrics.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[{
                "MetricName": name,
                "Dimensions": [{"Name": "Scanner", "Value": self.name}],
                "Value": value,
                "Unit": "Count",
            }],
        )

    def matches(self, tags: list[dict]) -> bool:
        values = {tag["Key"]: tag["Value"] for tag in tags}
        return all(values.get(key) == value for key, value in self.expected_tags.items())

    def discover(self) -> set[str]:
        inventory = set()
        if "S3" in self.resource_types:
            inventory.update(self._discover_s3())
        if "DynamoDB" in self.resource_types:
            inventory.update(self._discover_dynamodb())
        return inventory

    def _discover_s3(self) -> set[str]:
        inventory = set()
        for page in pages(
            self.s3.list_buckets, "ContinuationToken", "ContinuationToken",
            BucketRegion=self.region, MaxBuckets=1000,
        ):
            for bucket in page["Buckets"]:
                try:
                    tags = self.s3.get_bucket_tagging(
                        Bucket=bucket["Name"], ExpectedBucketOwner=self.account,
                    )["TagSet"]
                except ClientError as exc:
                    if exc.response["Error"]["Code"] != "NoSuchTagSet":
                        raise
                    LOGGER.info("Bucket %s has no tag set; excluded from expected inventory", bucket["Name"])
                    continue
                if self.matches(tags):
                    inventory.add(f"arn:{self.partition}:s3:::{bucket['Name']}")
        return inventory

    def _discover_dynamodb(self) -> set[str]:
        inventory = set()
        for page in pages(
            self.dynamodb.list_tables,
            "ExclusiveStartTableName", "LastEvaluatedTableName", Limit=100,
        ):
            for name in page["TableNames"]:
                if name == getattr(self.state, "table_name", None):
                    continue
                arn = f"arn:{self.partition}:dynamodb:{self.region}:{self.account}:table/{name}"
                tags = []
                for tag_page in pages(
                    self.dynamodb.list_tags_of_resource, "NextToken", "NextToken",
                    ResourceArn=arn,
                ):
                    tags.extend(tag_page["Tags"])
                if self.matches(tags):
                    inventory.add(arn)
        return inventory

    def notify(self, arn: str, event: str, reason: str, now: int):
        message = {
            "event": event, "resource_arn": arn, "reason": reason,
            "observed_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
            "scanner": self.name, "scope": "primary-region-snapshot",
        }
        self.sns.publish(
            TopicArn=self.topic_arn,
            Subject=f"AWS Backup coverage: {event}",
            Message=json.dumps(message, sort_keys=True),
        )
        LOGGER.info("Published coverage transition %s", json.dumps(message, sort_keys=True))

    def scan(self, now: int) -> dict:
        LOGGER.info("Coverage scan started for %s", self.name)
        self.metric("ScanStart", 1)
        try:
            return self._scan(now)
        except (ClientError, BotoCoreError, ValueError, RuntimeError, KeyError, TypeError):
            LOGGER.exception("Coverage scan failed for %s", self.name)
            try:
                self.metric("ScanFailure", 1)
            except (ClientError, BotoCoreError):
                LOGGER.exception("Could not publish scan-failure metric")
            raise

    def _latest_snapshot(self, arn: str, now: int) -> int | None:
        points = []
        try:
            for page in pages(
                self.backup.list_recovery_points_by_resource,
                "NextToken", "NextToken", ResourceArn=arn,
                ManagedByAWSBackupOnly=True, MaxResults=100,
            ):
                points.extend(page["RecoveryPoints"])
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
            LOGGER.warning("Independently discovered resource %s has no registered Backup recovery points", arn)
            points = []
        latest = latest_snapshot(points, self.region, self.account)
        if latest is not None and latest > now:
            raise ValueError("Recovery point timestamp is in the future")
        return latest

    def _notification_event(self, incident: bool, previous: dict, now: int) -> str | None:
        if not incident:
            return "recovered" if previous["incident"] else None
        if not previous["incident"]:
            return "opened"
        if (
            previous["last_notification"] is None
            or now - previous["last_notification"] >= self.policy.reminder_interval_seconds
        ):
            return "reminder"
        return None

    def _update_incident(self, arn: str, latest: int | None, previous: dict | None, now: int):
        if previous is None or not previous["active"]:
            initial = {
                "first_seen": now, "active": True, "incident": False,
                "last_notification": None, "reason": "initial",
            }
            self.state.save(arn, initial, previous)
            previous = initial
        if latest is None:
            within_grace = (
                not previous["incident"]
                and now - previous["first_seen"] < self.policy.initial_grace_seconds
            )
            reason = "grace" if within_grace else "missing"
        else:
            limit = self.policy.max_backup_age_seconds + self.policy.freshness_tolerance_seconds
            reason = "fresh" if now - latest <= limit else "stale"
        incident = reason in {"missing", "stale"}
        event = self._notification_event(incident, previous, now)
        updated = dict(previous, incident=incident, reason=reason)
        if event is not None:
            self.notify(arn, event, reason, now)
            updated["last_notification"] = now
        if updated != previous:
            self.state.save(arn, updated, previous)

    def _scan(self, now: int) -> dict:
        inventory = self.discover()
        freshness = {arn: self._latest_snapshot(arn, now) for arn in sorted(inventory)}

        # No incident or scope transition is committed from an incomplete scan.
        records = self.state.load()
        self.metric("InventorySize", len(inventory))
        for arn in sorted(inventory):
            self._update_incident(arn, freshness[arn], records.get(arn), now)

        for arn in sorted(records.keys() - inventory):
            previous = records[arn]
            if previous["active"]:
                self.notify(arn, "scope_removed", "not-in-expected-inventory", now)
                self.state.save(arn, dict(previous, active=False), previous)

        if not inventory:
            LOGGER.warning("Expected coverage inventory is empty for %s; this is not a coverage pass", self.name)
            self.metric("EmptyInventory", 1)
            return {"status": "EMPTY", "inventory_size": 0}
        self.metric("EmptyInventory", 0)
        self.metric("ScanSuccess", 1)
        LOGGER.info("Coverage scan completed for %s with %s expected resources", self.name, len(inventory))
        return {"status": "SCANNED", "inventory_size": len(inventory)}


def handler(event, context):
    config = json.loads(os.environ["COVERAGE_CONFIG"])
    policy = Policy(**{key: config["policy"][key] for key in (
        "max_backup_age_seconds", "freshness_tolerance_seconds",
        "initial_grace_seconds", "reminder_interval_seconds",
    )})
    session = boto3.Session(region_name=config["region"])
    sdk_config = Config(connect_timeout=5, read_timeout=10, retries={"mode": "standard", "max_attempts": 3})
    s3 = session.client("s3", config=sdk_config)
    if "S3" in config["resource_types"]:
        members = s3.meta.service_model.operation_model("ListBuckets").input_shape.members
        if not {"BucketRegion", "MaxBuckets", "ContinuationToken"} <= members.keys():
            raise RuntimeError("Runtime Boto3 lacks required paginated regional S3 ListBuckets support")
    dynamodb = session.client("dynamodb", config=sdk_config)
    scanner = Scanner(
        s3, dynamodb, session.client("backup", config=sdk_config), session.client("sns", config=sdk_config),
        session.client("cloudwatch", config=sdk_config), DynamoState(dynamodb, os.environ["STATE_TABLE"]),
        config["region"], config["account"], config["partition"],
        config["expected_tags"], set(config["resource_types"]), policy,
        config["topic_arn"], config["name"],
    )
    return scanner.scan(int(time.time()))
