"""Exercise the operator export entries with a captured PostgreSQL boundary."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BUSINESS = Path(__file__).resolve().parents[1]
source = Path(sys.argv.pop()) if len(sys.argv) == 2 and sys.argv[-1].endswith(".py") else BUSINESS / "databases/export_estimator_data.py"
spec = importlib.util.spec_from_file_location("exporter", source)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def rows(sql):
    if "FROM trade_rates" in sql:
        return [{"trade": "tiling", "wage": "45", "burden": "1.35", "markup": "1.6461"}]
    if "FROM jt_cost_codes" in sql:
        return [{"id": "code", "code": "1800"}]
    if "FROM jt_cost_types" in sql:
        return [{"id": "labor", "name": "Labor"}]
    if "FROM jt_units" in sql:
        return [{"id": "hours", "name": "Hours"}]
    if "FROM assembly_rules" in sql:
        return [{"rule_id": 26, "catalog_item_id": 27, "canonical_name": "Niche", "display_name": "Install niche",
                 "cost_code": "1800", "cost_type_name": "Labor", "unit_name": "Hours",
                 "default_qty": 1, "unit_cost": "60.75", "unit_price": "100", "waste_factor": "1",
                 "condition_trigger": "shower_niches > 0", "qty_formula": "shower_niches * 4",
                 "project_type": "bathroom", "sort_order": 26}]
    if "FROM catalog_items" in sql:
        return [{"id": 27, "canonical_name": "Niche", "unit_name": "Hours", "unit_cost": "60.75"}]
    if "FROM estimate_templates" in sql:
        return [{"id": 1, "name": "Fixture", "project_type": "bathroom", "state": {"shower_niches": 2}}]
    raise AssertionError("Unrecognized database read")


class CatalogExportTests(unittest.TestCase):
    def run_export(self, output, *, fail_templates=False):
        calls = []

        def run(command, **kwargs):
            self.assertEqual(command[:7], ["sudo", "-u", "postgres", "psql", "-d", "fixture-db", "-t"])
            self.assertEqual(kwargs, {"capture_output": True, "text": True, "timeout": 30})
            calls.append(command)
            sql = command[-1]
            if fail_templates and "FROM estimate_templates" in sql:
                return subprocess.CompletedProcess(command, 1, "", "fixture database unavailable")
            return subprocess.CompletedProcess(command, 0, json.dumps(rows(sql)), "")

        exporter.main(["--database", "fixture-db", "--output-dir", str(output)], run=run)
        return calls

    def test_all_outputs_use_postgres_and_preserve_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            self.assertEqual(len(self.run_export(output)), 7)
            self.assertEqual({p.name for p in output.iterdir()}, {
                "tradeRates.json", "jtMappings.json", "catalog.json", "pricebook.json", "catalog_export.json", "templates.json"})
            read = lambda name: json.loads((output / name).read_text())
            self.assertEqual(read("tradeRates.json"), {"tiling": {"wage": 45.0, "burden": 1.35, "markup": 1.6461}})
            self.assertEqual(read("jtMappings.json"), {"codes": {"1800": "code"}, "types": {"Labor": "labor"}, "units": {"Hours": "hours"}})
            item = read("catalog.json")[0]
            self.assertEqual((item["id"], item["ruleId"], item["name"], item["unitAbbr"], item["unitCost"]), (27, 26, "Install niche", "hrs", 60.75))
            self.assertEqual(read("pricebook.json")[0]["unitCost"], 60.75)
            self.assertEqual(read("templates.json")[0]["state"], {"shower_niches": 2})
            self.assertEqual((output / "catalog.json").stat().st_mode & 0o777, 0o644)
            (output / "catalog.json").chmod(0o640)
            self.run_export(output)
            self.assertEqual((output / "catalog.json").stat().st_mode & 0o777, 0o640)

    def test_failed_read_preserves_previous_export_set(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            self.run_export(output)
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            with self.assertRaisesRegex(RuntimeError, "fixture database unavailable"):
                self.run_export(output, fail_templates=True)
            self.assertEqual({p.name: p.read_bytes() for p in output.iterdir()}, before)

    def test_operator_entries_reach_canonical_cli_without_database_access(self):
        for entry in [BUSINESS / "estimator/scripts/export_catalog.py", BUSINESS / "estimator/scripts/export_catalog.sh"]:
            command = [sys.executable] if entry.suffix == ".py" else ["bash"]
            result = subprocess.run(command + [str(entry), "--help"], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--database", result.stdout)
            self.assertIn("--output-dir", result.stdout)


if __name__ == "__main__":
    unittest.main()
