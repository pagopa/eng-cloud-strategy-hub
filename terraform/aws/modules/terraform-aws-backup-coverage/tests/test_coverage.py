import importlib.util
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import Mock

from botocore.exceptions import ClientError
from botocore.session import get_session


SPEC = importlib.util.spec_from_file_location(
    "coverage_runtime", Path(__file__).parents[1] / "lambda" / "coverage.py"
)
coverage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = coverage
SPEC.loader.exec_module(coverage)

ACCOUNT = "123456789012"
REGION = "eu-south-1"
TABLE = f"arn:aws:dynamodb:{REGION}:{ACCOUNT}:table/orders"
BUCKET = "arn:aws:s3:::orders"
TOPIC = f"arn:aws:sns:{REGION}:{ACCOUNT}:alerts"
POINT = f"arn:aws:backup:{REGION}:{ACCOUNT}:recovery-point:snapshot-1"


def error(code):
    return ClientError({"Error": {"Code": code, "Message": code}}, "test")


def point(age=0, status="COMPLETED", arn=POINT):
    return {
        "RecoveryPointArn": arn,
        "CreationDate": datetime.fromtimestamp(10000 - age, timezone.utc),
        "Status": status,
    }


class MemoryState:
    def __init__(self):
        self.items = {}

    def load(self):
        return {arn: dict(item) for arn, item in self.items.items()}

    def save(self, arn, item, previous):
        if self.items.get(arn) != previous:
            raise RuntimeError("concurrent state modification")
        self.items[arn] = dict(item)


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.s3 = Mock()
        self.ddb = Mock()
        self.backup = Mock()
        self.sns = Mock()
        self.metrics = Mock()
        self.s3.list_buckets.return_value = {"Buckets": [{"Name": "orders"}]}
        self.s3.get_bucket_tagging.return_value = {
            "TagSet": [{"Key": "workload", "Value": "orders"}]
        }
        self.ddb.list_tables.return_value = {"TableNames": ["orders"]}
        self.ddb.list_tags_of_resource.return_value = {
            "Tags": [{"Key": "workload", "Value": "orders"}]
        }
        self.backup.list_recovery_points_by_resource.return_value = {
            "RecoveryPoints": []
        }
        self.state = MemoryState()
        self.policy = coverage.Policy(3600, 60, 300, 1800)
        self.scanner = coverage.Scanner(
            self.s3, self.ddb, self.backup, self.sns, self.metrics, self.state,
            REGION, ACCOUNT, "aws", {"workload": "orders"},
            {"DynamoDB", "S3"}, self.policy, TOPIC, "test-coverage",
        )

    def scan(self, now=10000):
        return self.scanner.scan(now)

    def messages(self):
        return [json.loads(call.kwargs["Message"])
                for call in self.sns.publish.call_args_list]

    def test_never_backed_up_is_discovered_and_alerted_after_grace(self):
        result = self.scan()
        self.assertEqual(result["inventory_size"], 2)
        self.sns.publish.assert_not_called()
        self.scan(10300)
        self.assertEqual({m["event"] for m in self.messages()}, {"opened"})
        self.assertEqual({m["resource_arn"] for m in self.messages()}, {TABLE, BUCKET})
        self.assertTrue(all(m["reason"] == "missing" for m in self.messages()))

    def test_fresh_snapshots_are_not_incidents(self):
        self.backup.list_recovery_points_by_resource.return_value = {
            "RecoveryPoints": [point(3600)]
        }
        self.scan()
        self.sns.publish.assert_not_called()
        self.assertFalse(any(s["incident"] for s in self.state.items.values()))

    def test_stale_snapshot_does_not_receive_never_backed_up_grace(self):
        self.backup.list_recovery_points_by_resource.return_value = {
            "RecoveryPoints": [point(3661)]
        }
        self.scan()
        self.assertEqual(len(self.messages()), 2)
        self.assertTrue(all(m["reason"] == "stale" for m in self.messages()))

    def test_grace_cannot_close_an_incident_without_fresh_snapshot(self):
        self.backup.list_recovery_points_by_resource.return_value = {"RecoveryPoints": [point(3661)]}
        self.scan()
        self.backup.list_recovery_points_by_resource.return_value = {"RecoveryPoints": []}
        self.scan(10001)
        self.assertTrue(all(s["incident"] for s in self.state.items.values()))
        self.assertNotIn("recovered", [m["event"] for m in self.messages()])

    def test_declared_sdk_has_required_pagination_and_backup_inputs(self):
        session = get_session()
        for service, operation, expected in (
            ("s3", "ListBuckets", {"BucketRegion", "MaxBuckets", "ContinuationToken"}),
            ("backup", "ListRecoveryPointsByResource", {"ResourceArn", "NextToken", "ManagedByAWSBackupOnly"}),
        ):
            with self.subTest(service=service):
                members = session.get_service_model(service).operation_model(operation).input_shape.members
                self.assertTrue(expected <= members.keys())

    def test_freshness_exact_boundary_and_one_second_over(self):
        self.backup.list_recovery_points_by_resource.return_value = {
            "RecoveryPoints": [point(3660)]
        }
        self.scan()
        self.sns.publish.assert_not_called()
        self.scan(10001)
        self.assertEqual(len(self.messages()), 2)

    def test_non_usable_points_do_not_mask_missing_snapshot(self):
        for status in ("PARTIAL", "DELETING", "EXPIRED", "CREATING", "STOPPED"):
            with self.subTest(status=status):
                self.assertIsNone(coverage.latest_snapshot([point(status=status)], REGION, ACCOUNT))

    def test_unregistered_backup_resource_is_missing_not_scan_failure(self):
        self.backup.list_recovery_points_by_resource.side_effect = error("ResourceNotFoundException")
        self.scan()
        self.scan(10300)
        self.assertEqual(len(self.messages()), 2)
        self.assertTrue(all(m["reason"] == "missing" for m in self.messages()))

    def test_invalid_status_and_policy_fail_explicitly(self):
        with self.assertRaises(ValueError):
            coverage.latest_snapshot([point(status="UNKNOWN")], REGION, ACCOUNT)
        for values in ((0, 0, 0, 1), (60, 60, 0, 1), (60, 0, -1, 1), (60, 0, 0, 0), (60.5, 0, 0, 1)):
            with self.subTest(values=values), self.assertRaises(ValueError):
                coverage.Policy(*values)

    def test_incident_table_is_excluded_from_own_discovery(self):
        self.state.table_name = "orders"
        self.scanner.resource_types = {"DynamoDB"}
        self.assertEqual(self.scan()["status"], "EMPTY")
        self.ddb.list_tags_of_resource.assert_not_called()

    def test_continuous_recovery_point_is_not_snapshot(self):
        arn = f"arn:aws:backup:{REGION}:{ACCOUNT}:recovery-point:continuous:orders"
        self.assertIsNone(coverage.latest_snapshot([point(arn=arn)], REGION, ACCOUNT))

    def test_dynamodb_snapshot_shape(self):
        arn = f"arn:aws:dynamodb:{REGION}:{ACCOUNT}:table/orders/backup/012345"
        self.assertEqual(coverage.latest_snapshot([point(arn=arn)], REGION, ACCOUNT), 10000)

    def test_foreign_region_and_account_are_excluded(self):
        self.assertIsNone(coverage.latest_snapshot([
            point(arn=POINT.replace(REGION, "eu-west-1")),
            point(arn=POINT.replace(ACCOUNT, "999999999999")),
        ], REGION, ACCOUNT))

    def test_unknown_snapshot_shape_and_missing_timestamp_fail_explicitly(self):
        with self.assertRaises(ValueError):
            coverage.latest_snapshot([point(arn="unexpected")], REGION, ACCOUNT)
        recovery = point()
        del recovery["CreationDate"]
        with self.assertRaises(ValueError):
            coverage.latest_snapshot([recovery], REGION, ACCOUNT)

    def test_future_timestamp_is_not_a_freshness_pass(self):
        self.backup.list_recovery_points_by_resource.return_value = {
            "RecoveryPoints": [point(-1)]
        }
        with self.assertRaises(ValueError):
            self.scan()
        self.assertFalse(self.state.items)

    def test_all_inventory_and_backup_pagination(self):
        self.s3.list_buckets.side_effect = [
            {"Buckets": [], "ContinuationToken": "s3-next"},
            {"Buckets": [{"Name": "orders"}]},
        ]
        self.ddb.list_tables.side_effect = [
            {"TableNames": [], "LastEvaluatedTableName": "previous"},
            {"TableNames": ["orders"]},
        ]
        self.ddb.list_tags_of_resource.side_effect = [
            {"Tags": [], "NextToken": "tag-next"},
            {"Tags": [{"Key": "workload", "Value": "orders"}]},
        ]
        self.backup.list_recovery_points_by_resource.side_effect = [
            {"RecoveryPoints": [], "NextToken": "backup-next"},
            {"RecoveryPoints": [point()]},
            {"RecoveryPoints": [point()]},
        ]
        self.scan()
        self.assertEqual(self.s3.list_buckets.call_args_list[1].kwargs["ContinuationToken"], "s3-next")
        self.assertEqual(self.s3.list_buckets.call_args_list[0].kwargs["BucketRegion"], REGION)
        self.assertEqual(self.ddb.list_tables.call_args_list[1].kwargs["ExclusiveStartTableName"], "previous")
        self.assertEqual(self.ddb.list_tags_of_resource.call_args_list[1].kwargs["NextToken"], "tag-next")
        self.assertEqual(self.backup.list_recovery_points_by_resource.call_args_list[1].kwargs["NextToken"], "backup-next")
        self.assertTrue(all(c.kwargs["ManagedByAWSBackupOnly"] for c in self.backup.list_recovery_points_by_resource.call_args_list))

    def test_repeated_pagination_token_fails(self):
        self.s3.list_buckets.return_value = {"Buckets": [], "ContinuationToken": "same"}
        with self.assertRaises(RuntimeError):
            self.scan()

    def test_tags_match_all_pairs_and_scope_is_explicit(self):
        self.scanner.expected_tags["environment"] = "prod"
        self.assertEqual(self.scan()["status"], "EMPTY")
        self.sns.publish.assert_not_called()
        self.scanner.resource_types = {"S3"}
        self.scanner.expected_tags = {"workload": "orders"}
        self.scan()
        self.assertEqual(set(self.state.items), {BUCKET})

    def test_unsupported_type_and_empty_configuration_fail(self):
        with self.assertRaises(ValueError):
            coverage.validate_configuration({}, {"S3"}, self.policy)
        with self.assertRaises(ValueError):
            coverage.validate_configuration({"workload": "orders"}, {"EC2"}, self.policy)
        with self.assertRaises(ValueError):
            coverage.validate_configuration({"workload": "orders"}, set(), self.policy)

    def test_empty_inventory_has_diagnostic_without_success(self):
        self.s3.list_buckets.return_value = {"Buckets": []}
        self.ddb.list_tables.return_value = {"TableNames": []}
        result = self.scan()
        self.assertEqual(result["status"], "EMPTY")
        names = [m["MetricName"] for c in self.metrics.put_metric_data.call_args_list
                 for m in c.kwargs["MetricData"]]
        self.assertIn("EmptyInventory", names)
        self.assertNotIn("ScanSuccess", names)

    def test_untagged_s3_bucket_is_not_permission_failure(self):
        self.s3.get_bucket_tagging.side_effect = error("NoSuchTagSet")
        self.scanner.resource_types = {"S3"}
        self.assertEqual(self.scan()["status"], "EMPTY")

    def test_discovery_and_backup_errors_do_not_mutate_or_close_incidents(self):
        self.scan()
        self.scan(10300)
        before = self.state.load()
        for client, method in (
            (self.s3, "list_buckets"),
            (self.s3, "get_bucket_tagging"),
            (self.ddb, "list_tables"),
            (self.ddb, "list_tags_of_resource"),
            (self.backup, "list_recovery_points_by_resource"),
        ):
            with self.subTest(method=method):
                getattr(client, method).side_effect = error("AccessDeniedException")
                with self.assertRaises(ClientError):
                    self.scan(11000)
                self.assertEqual(self.state.items, before)
                getattr(client, method).side_effect = None

    def test_deduplication_reminder_and_recovery(self):
        self.scan()
        self.scan(10300)
        self.scan(10300)
        self.assertEqual(len(self.messages()), 2)
        self.scan(12099)
        self.assertEqual(len(self.messages()), 2)
        self.scan(12100)
        self.assertEqual([m["event"] for m in self.messages()].count("reminder"), 2)
        self.backup.list_recovery_points_by_resource.return_value = {"RecoveryPoints": [point()]}
        self.scan(12101)
        self.scan(12101)
        self.assertEqual([m["event"] for m in self.messages()].count("recovered"), 2)

    def test_resource_removal_is_scope_change_and_reentry_gets_new_grace(self):
        self.scan()
        self.scan(10300)
        self.s3.list_buckets.return_value = {"Buckets": []}
        self.scan(10400)
        removed = [m for m in self.messages() if m["event"] == "scope_removed"]
        self.assertEqual([m["resource_arn"] for m in removed], [BUCKET])
        self.assertTrue(self.state.items[BUCKET]["incident"])
        self.assertFalse(self.state.items[BUCKET]["active"])
        self.s3.list_buckets.return_value = {"Buckets": [{"Name": "orders"}]}
        self.scan(10500)
        self.assertEqual(self.state.items[BUCKET]["first_seen"], 10500)
        self.assertFalse(self.state.items[BUCKET]["incident"])

    def test_failed_publication_does_not_record_delivery(self):
        self.scan()
        self.sns.publish.side_effect = error("KMSAccessDenied")
        with self.assertRaises(ClientError):
            self.scan(10300)
        self.assertTrue(all(s["last_notification"] is None for s in self.state.items.values()))
        self.sns.publish.side_effect = None
        self.scan(10300)
        self.assertTrue(all(s["incident"] for s in self.state.items.values()))

    def test_failed_recovery_publication_is_retried(self):
        self.scan()
        self.scan(10300)
        self.backup.list_recovery_points_by_resource.return_value = {"RecoveryPoints": [point()]}
        self.sns.publish.side_effect = error("InternalError")
        with self.assertRaises(ClientError):
            self.scan(10400)
        self.assertTrue(all(s["incident"] for s in self.state.items.values()))
        self.sns.publish.side_effect = None
        self.scan(10400)
        self.assertTrue(all(not s["incident"] for s in self.state.items.values()))

    def test_conditional_state_conflict_fails_instead_of_losing_alert(self):
        self.state.save = Mock(side_effect=RuntimeError("concurrent state modification"))
        with self.assertRaises(RuntimeError):
            self.scan()
        self.sns.publish.assert_not_called()

    def test_state_store_paginates_and_uses_conditional_writes(self):
        client = Mock()
        client.scan.side_effect = [
            {"Items": [], "LastEvaluatedKey": {"resource_arn": {"S": TABLE}}},
            {"Items": [{"resource_arn": {"S": TABLE}, "payload": {"S": '{"first_seen":1}'}}]},
        ]
        store = coverage.DynamoState(client, "state")
        self.assertEqual(store.load(), {TABLE: {"first_seen": 1}})
        self.assertTrue(client.scan.call_args_list[0].kwargs["ConsistentRead"])
        store.save(TABLE, {"first_seen": 2}, {"first_seen": 1})
        self.assertEqual(client.put_item.call_args.kwargs["ConditionExpression"], "#payload = :previous")
        store.save(BUCKET, {"first_seen": 2}, None)
        self.assertEqual(client.put_item.call_args.kwargs["ConditionExpression"], "attribute_not_exists(resource_arn)")

    def test_metric_failure_is_explicit(self):
        self.metrics.put_metric_data.side_effect = error("AccessDenied")
        with self.assertRaises(ClientError):
            self.scan()
        self.assertFalse(self.state.items)


if __name__ == "__main__":
    unittest.main()
