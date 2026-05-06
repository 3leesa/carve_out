import argparse
import csv
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape, unescape


# Default working folder used in `prepare` mode to write the modified metadata
# before anything is copied back into the Salesforce project.
DEFAULT_WORK_DIR = ".carve_out_work"

# Default timeout for Salesforce CLI calls. The script performs retrieve/query/deploy
# operations, so we keep these values centralized for easier tuning.
DEFAULT_SF_TIMEOUT_SECONDS = 300

# Salesforce SOQL/tooling queries can become too large if too many labels are queried
# in one request, so labels are fetched in batches.
MAX_SOQL_LABELS_PER_QUERY = 100

# The script retrieves metadata by type/member. We batch those calls to reduce the
# chance of hitting CLI/API limits or creating huge command lines.
MAX_RETRIEVE_METADATA_MEMBERS_PER_BATCH = 20

# Same batching idea for deploys: deploy a manageable number of source dirs per call.
MAX_DEPLOY_SOURCE_DIRS_PER_BATCH = 20

# The input CSV must match this exact schema and column order.
CSV_HEADERS = ["objectApiName", "componentName", "settingType", "targetName", "template"]

# Supported operations the script knows how to change in metadata files.
# Each settingType maps to a specific XML tag or XML structure later in the script.
SUPPORTED_SETTING_TYPES = {
    "defaultValue",
    "description",
    "fieldLabel",
    "formula",
    "helpText",
    "picklistLabel",
    "relatedListLabel",
    "listViewLabel",
    "listViewFilterValue",
    "webLinkUrl",
    "validationRuleFormula",
}

# Supported List View filter operators for `listViewFilterValue`.
# These are validated early so wrong values fail before any retrieve/deploy happens.
SUPPORTED_FILTER_OPERATIONS = {
    "contains",
    "equals",
    "notEqual",
    "notContains",
    "startsWith",
    "includes",
    "excludes",
    "lessThan",
    "greaterThan",
    "lessOrEqual",
    "greaterOrEqual",
}

# Some picklists are not stored under the field metadata file. For standard Salesforce
# value sets, the label must be updated in `standardValueSets/*.standardValueSet-meta.xml`.
STANDARD_VALUE_SET_FIELDS = {
    ("Lead", "LeadSource"): "LeadSource",
}


def fail(message):
    # Small helper for "fatal" user-facing validation errors.
    # We print to stderr so shells/pipelines can distinguish failures from normal output.
    print(message, file=sys.stderr)
    sys.exit(1)


def format_batch_summary(batch_number, batch_size, paths):
    # Produces a readable multi-line summary used when a deploy batch fails.
    lines = [f"- batch {batch_number}: {batch_size} file(s)"]
    for path in paths:
        lines.append(f"  - {path}")
    return "\n".join(lines)


def run_sf(args, timeout_seconds=DEFAULT_SF_TIMEOUT_SECONDS):
    # Central wrapper around the Salesforce CLI (`sf` / `sf.cmd` on Windows).
    # Every CLI call goes through here so timeout handling and error formatting stay
    # consistent across retrieve/query/deploy operations.
    executable = "sf.cmd" if os.name == "nt" else "sf"
    cmd = [executable] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, shell=False, timeout=timeout_seconds)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"Command timed out after {timeout_seconds} seconds: {' '.join(cmd)}"
        ) from exc
    if result.returncode != 0:
        raise RuntimeError(
            "\n".join(
                part
                for part in [
                    f"Command failed: {' '.join(cmd)}",
                    result.stdout.strip(),
                    result.stderr.strip(),
                ]
                if part
            )
        )
    return result.stdout


def read_csv(csv_path):
    # Reads the input mapping CSV. The file may use comma or semicolon separators,
    # so we sniff the delimiter first and then validate the exact header names/order.
    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        sample = f.read(4096)
        f.seek(0)

        first_line = next((line for line in sample.splitlines() if line.strip()), "")
        if first_line.count(";") > first_line.count(","):
            delimiter = ";"
        elif first_line.count(",") > first_line.count(";"):
            delimiter = ","
        else:
            try:
                delimiter = csv.Sniffer().sniff(sample, delimiters=",;").delimiter
            except csv.Error:
                delimiter = ","

        reader = csv.DictReader(f, delimiter=delimiter)
        fieldnames = [name.strip() for name in (reader.fieldnames or [])]

        if fieldnames != CSV_HEADERS:
            fail(
                "CSV headers must be exactly:\n"
                f"- {', '.join(CSV_HEADERS)}\n"
                f"Found: {fieldnames}\n"
                "Accepted separators: comma (,) or semicolon (;)"
            )
        rows = [normalize_row(row, i) for i, row in enumerate(reader, start=2)]

    for row in rows:
        validate_row(row)
    return rows


def normalize_row(row, line_number):
    # Trim whitespace from every CSV cell and keep the original line number for
    # precise error messages later.
    normalized = {key: (value or "").strip() for key, value in row.items()}
    normalized["_line"] = line_number
    return normalized


def suggest_value(value, allowed_values):
    # Used only for friendlier validation messages, e.g. typo suggestions in settingType.
    matches = difflib.get_close_matches(value, sorted(allowed_values), n=1, cutoff=0.6)
    return matches[0] if matches else ""


def validate_api_name(value, field_name, line_number):
    # Basic Salesforce API name validation.
    # We intentionally allow standard names and common custom suffixes.
    if not value:
        return
    if not re.fullmatch(r"[A-Za-z0-9_]+(__c|__mdt|__e|__x)?", value):
        raise RuntimeError(
            f"CSV line {line_number}: invalid {field_name} '{value}'. "
            f"Use the Salesforce API/developer name only."
        )


def validate_list_view_field_name(value, line_number):
    # List view filters may target either a direct field (`Status__c`) or a dotted
    # relationship-style path (`RecordType.Name`-like shape), so this validator is
    # slightly more permissive than `validate_api_name`.
    if not value:
        return
    if re.fullmatch(r"[A-Za-z0-9_]+(__c|__mdt|__e|__x)?", value):
        return
    if re.fullmatch(r"[A-Za-z0-9_]+\.[A-Za-z0-9_]+(__c|__mdt|__e|__x)?", value):
        return
    raise RuntimeError(
        f"CSV line {line_number}: invalid list view filter field '{value}'. "
        "Use the Salesforce API/developer name only."
    )


def validate_template(row):
    # The `template` column is the desired target value. It can contain literal text
    # plus custom-label placeholders like `{{My_Label}}`, so we validate both that
    # the placeholder markers are balanced and that label tokens are safe.
    template = row["template"]
    if not template:
        raise RuntimeError(f"CSV line {row['_line']}: template is required.")

    opens = template.count("{{")
    closes = template.count("}}")
    if opens != closes:
        raise RuntimeError(
            f"CSV line {row['_line']}: template has unmatched custom label markers in '{template}'."
        )

    invalid_tokens = re.findall(r"\{\{([^{}]+)\}\}", template)
    for token in invalid_tokens:
        if not re.fullmatch(r"[A-Za-z0-9_]+", token):
            raise RuntimeError(
                f"CSV line {row['_line']}: invalid custom label token '{{{{{token}}}}}'. "
                "Only letters, numbers, and underscores are allowed."
            )


def validate_row(row):
    # Validates one CSV row before any metadata is retrieved.
    # This is intentionally strict so mistakes are caught early and clearly.
    setting_type = row["settingType"]
    if setting_type not in SUPPORTED_SETTING_TYPES:
        suggestion = suggest_value(setting_type, SUPPORTED_SETTING_TYPES)
        suggestion_message = f" Did you mean '{suggestion}'?" if suggestion else ""
        raise RuntimeError(
            f"CSV line {row['_line']}: unsupported settingType '{setting_type}'. "
            f"Supported values: {', '.join(sorted(SUPPORTED_SETTING_TYPES))}.{suggestion_message}"
        )

    validate_template(row)
    validate_api_name(row["objectApiName"], "objectApiName", row["_line"])
    validate_api_name(row["componentName"], "componentName", row["_line"])

    if not row["objectApiName"]:
        raise RuntimeError(f"CSV line {row['_line']}: objectApiName is required.")
    if not row["componentName"]:
        raise RuntimeError(f"CSV line {row['_line']}: componentName is required.")

    if setting_type in {"picklistLabel", "listViewFilterValue"} and not row["targetName"]:
        raise RuntimeError(f"CSV line {row['_line']}: targetName is required for settingType '{setting_type}'.")

    if setting_type == "picklistLabel" and row["targetName"] and "|" in row["targetName"]:
        raise RuntimeError(
            f"CSV line {row['_line']}: invalid targetName '{row['targetName']}' for picklistLabel. "
            "Use only the picklist value API name."
        )

    if setting_type != "listViewFilterValue" and "|" in row["targetName"]:
        raise RuntimeError(
            f"CSV line {row['_line']}: targetName '{row['targetName']}' looks like a list view filter target, "
            f"but settingType is '{setting_type}'."
        )

    if setting_type == "listViewFilterValue":
        parse_filter_target(row["targetName"], row["_line"])


def group_by_component(rows):
    # Multiple CSV rows may target the same metadata file (for example several updates
    # to the same field or list view). We group them so the file is read/updated once.
    grouped = {}
    for row in rows:
        key = resolve_group_key(row)
        grouped.setdefault(key, []).append(row)
    return grouped


def resolve_picklist_storage(row):
    # Decides whether a picklist label lives in the field metadata file or in a
    # separate Standard Value Set metadata file.
    standard_value_set_name = STANDARD_VALUE_SET_FIELDS.get((row["objectApiName"], row["componentName"]))
    if row["settingType"] == "picklistLabel" and standard_value_set_name:
        return {"kind": "standardValueSet", "name": standard_value_set_name}
    return {"kind": "field"}


def resolve_group_key(row):
    # `group_key` is the relative path of the metadata file that this row will touch.
    return build_default_relative_path(
        row["objectApiName"],
        row["componentName"],
        row["settingType"],
        row=row,
    ).as_posix()


def build_default_relative_path(object_api_name, component_name, setting_type, row=None):
    # Converts a CSV row definition into the expected Salesforce metadata file path.
    # This path is used both after retrieve (to locate the downloaded file) and during
    # prepare/deploy (to know where the updated file belongs in the project).
    if setting_type == "picklistLabel" and row:
        storage = resolve_picklist_storage(row)
        if storage["kind"] == "standardValueSet":
            return (
                Path("force-app")
                / "main"
                / "default"
                / "standardValueSets"
                / f"{storage['name']}.standardValueSet-meta.xml"
            )
    if setting_type in {
        "fieldLabel",
        "helpText",
        "defaultValue",
        "description",
        "formula",
        "picklistLabel",
        "relatedListLabel",
    }:
        return Path("force-app") / "main" / "default" / "objects" / object_api_name / "fields" / f"{component_name}.field-meta.xml"
    if setting_type in {"listViewLabel", "listViewFilterValue"}:
        return Path("force-app") / "main" / "default" / "objects" / object_api_name / "listViews" / f"{component_name}.listView-meta.xml"
    if setting_type == "webLinkUrl":
        return Path("force-app") / "main" / "default" / "objects" / object_api_name / "webLinks" / f"{component_name}.webLink-meta.xml"
    if setting_type == "validationRuleFormula":
        return Path("force-app") / "main" / "default" / "objects" / object_api_name / "validationRules" / f"{component_name}.validationRule-meta.xml"
    raise RuntimeError(f"Unsupported settingType '{setting_type}'.")


def get_metadata_member(row):
    # Builds the `Type:Member` syntax expected by `sf project retrieve start --metadata`.
    setting_type = row["settingType"]
    if setting_type == "picklistLabel":
        storage = resolve_picklist_storage(row)
        if storage["kind"] == "standardValueSet":
            return f"StandardValueSet:{storage['name']}"

    if setting_type in {
        "fieldLabel",
        "helpText",
        "defaultValue",
        "description",
        "formula",
        "picklistLabel",
        "relatedListLabel",
    }:
        return f"CustomField:{row['objectApiName']}.{row['componentName']}"

    if setting_type in {"listViewLabel", "listViewFilterValue"}:
        return f"ListView:{row['objectApiName']}.{row['componentName']}"

    if setting_type == "webLinkUrl":
        return f"WebLink:{row['objectApiName']}.{row['componentName']}"

    if setting_type == "validationRuleFormula":
        return f"ValidationRule:{row['objectApiName']}.{row['componentName']}"

    raise RuntimeError(f"Unsupported settingType '{setting_type}'.")


def retrieve_metadata_batch(alias, rows, timeout_seconds):
    # Retrieves all metadata components required by the CSV.
    # We de-duplicate first because several rows may point to the same component.
    print(f"\n[DEBUG] Starting metadata retrieval for : {rows}")
    metadata_members = sorted({get_metadata_member(row) for row in rows})
    print(f"\n[DEBUG] Unique metadata members identified: {metadata_members}")

    if not metadata_members:
        print("[DEBUG] No metadata members to retrieve. Skipping.")
        return

    for batch_number, batch in enumerate(
        chunked(metadata_members, MAX_RETRIEVE_METADATA_MEMBERS_PER_BATCH), start=1
    ):
        print(f"\n[DEBUG] --- Processing Batch #{batch_number} ---")
        print(f"[DEBUG] Batch size: {len(batch)}")
        print(f"[DEBUG] Batch contents: {batch}")

        args = [
            "project",
            "retrieve",
            "start",
            "--target-org",
            alias,
            "--json",
        ]
        for member in batch:
            args.extend(["--metadata", member])

        print(f"[DEBUG] Constructing CLI arguments: {' '.join(args)}")
        # run_sf(args, timeout_seconds=timeout_seconds)


def deploy_files(alias, file_paths, timeout_seconds):
    # Deploys prepared files in batches. If one batch fails, we include a summary of
    # what already succeeded so the operator knows where to resume/investigate.
    deploy_paths = [str(path) for path in file_paths]
    if not deploy_paths:
        return

    succeeded_batches = []
    for batch_number, batch in enumerate(chunked(deploy_paths, MAX_DEPLOY_SOURCE_DIRS_PER_BATCH), start=1):
        print(
            f"Deploying batch {batch_number} with {len(batch)} prepared file(s)..."
        )
        args = [
            "project",
            "deploy",
            "start",
            "--target-org",
            alias,
            "--json",
        ]
        for file_path in batch:
            args.extend(["--source-dir", file_path])
        try:
            run_sf(args, timeout_seconds=timeout_seconds)
            succeeded_batches.append((batch_number, list(batch)))
        except RuntimeError as exc:
            summary_lines = [
                f"Deploy failed on batch {batch_number} with {len(batch)} file(s).",
            ]
            if succeeded_batches:
                summary_lines.append("\nPreviously deployed batches:")
                summary_lines.extend(
                    format_batch_summary(index, len(paths), paths)
                    for index, paths in succeeded_batches
                )
            summary_lines.append("\nFailed batch:")
            summary_lines.append(format_batch_summary(batch_number, len(batch), batch))
            summary_lines.append("\nSalesforce CLI error:")
            summary_lines.append(str(exc))
            raise RuntimeError("\n".join(summary_lines)) from None


def get_label_value(alias, label_name):
    # Fetches a single Custom Label value from Salesforce using the Tooling API.
    # In normal runs labels are prefetched in bulk, but this remains as a fallback.
    safe_label_name = label_name.replace("'", "\\'")
    soql = f"SELECT Value FROM ExternalString WHERE Name = '{safe_label_name}'"
    output = run_sf(
        [
            "data",
            "query",
            "--use-tooling-api",
            "--query",
            soql,
            "--target-org",
            alias,
            "--json",
        ]
    )
    parsed = json.loads(output)
    records = parsed.get("result", {}).get("records", [])
    if len(records) != 1:
        raise RuntimeError(f"Custom Label not found or not unique: {label_name}")
    return records[0]["Value"]


def extract_label_names(rows):
    # Scans all templates and extracts every unique `{{Label_Name}}` token.
    label_names = set()
    for row in rows:
        label_names.update(re.findall(r"\{\{([A-Za-z0-9_]+)\}\}", row["template"]))
    return sorted(label_names)


def chunked(items, size):
    # Generic batching helper used for labels, retrieves, and deploys.
    for index in range(0, len(items), size):
        yield items[index : index + size]


def prefetch_label_values(alias, rows, timeout_seconds):
    # Resolves every label token up front. This reduces repeated CLI calls and makes
    # failures deterministic before we start editing metadata files.
    label_names = extract_label_names(rows)
    if not label_names:
        return {}

    cache = {}
    for batch in chunked(label_names, MAX_SOQL_LABELS_PER_QUERY):
        escaped_names = [name.replace("'", "\\'") for name in batch]
        in_clause = ", ".join(f"'{name}'" for name in escaped_names)
        soql = f"SELECT Name, Value FROM ExternalString WHERE Name IN ({in_clause})"
        output = run_sf(
            [
                "data",
                "query",
                "--use-tooling-api",
                "--query",
                soql,
                "--target-org",
                alias,
                "--json",
            ],
            timeout_seconds=timeout_seconds,
        )
        parsed = json.loads(output)
        records = parsed.get("result", {}).get("records", [])
        for record in records:
            cache[record["Name"]] = record["Value"]

        missing = [name for name in batch if name not in cache]
        if missing:
            raise RuntimeError(
                "Custom Label not found or not unique: " + ", ".join(sorted(missing))
            )
    return cache


def resolve_template(template, alias, cache):
    # Replaces every `{{Custom_Label}}` token in the template with the current value
    # from Salesforce, preserving any surrounding literal text.
    def repl(match):
        label_name = match.group(1)
        if label_name not in cache:
            cache[label_name] = get_label_value(alias, label_name)
        return cache[label_name]

    return re.sub(r"\{\{([A-Za-z0-9_]+)\}\}", repl, template)


def get_file_path(project_root, group_key):
    # After retrieve, Salesforce writes files into the local project structure.
    # This helper verifies the expected file exists before we try to read it.
    path = project_root / Path(group_key)
    if not path.exists():
        raise RuntimeError(f"Retrieved metadata not found: {path}")
    return path


def get_tag_value(xml_text, tag_name):
    # Lightweight XML extraction helper.
    # This script uses regex/string replacement instead of a full XML parser because
    # Salesforce metadata files are predictable and we want to preserve formatting.
    match = re.search(rf"<{tag_name}>([\s\S]*?)</{tag_name}>", xml_text)
    return unescape(match.group(1)) if match else ""


def replace_tag(xml_text, tag_name, new_value, root_tag):
    # Replaces the first matching XML tag value, or inserts the tag before the closing
    # root element if the tag does not exist yet.
    escaped = escape(str(new_value), {"'": "&apos;", '"': "&quot;"})
    pattern = rf"<{tag_name}>[\s\S]*?</{tag_name}>"
    replacement = f"<{tag_name}>{escaped}</{tag_name}>"
    if re.search(pattern, xml_text):
        return re.sub(pattern, replacement, xml_text, count=1)
    return xml_text.replace(f"</{root_tag}>", f"    {replacement}\n</{root_tag}>")


def get_picklist_label(xml_text, target_name):
    # For custom-field picklists, each value lives inside a `<value>...</value>` block.
    # We locate the block whose `<fullName>` matches the target value API name.
    blocks = re.findall(r"<value>[\s\S]*?</value>", xml_text)
    matches = [block for block in blocks if get_tag_value(block, "fullName") == target_name]
    if len(matches) != 1:
        raise RuntimeError(f"Could not uniquely find picklist value '{target_name}' in metadata.")
    match = re.search(r"<label>([\s\S]*?)</label>", matches[0])
    return unescape(match.group(1)) if match else ""


def update_picklist_label(xml_text, target_name, new_label):
    # Updates exactly one custom picklist value label.
    # If zero or multiple blocks match, we fail rather than guessing.
    escaped = escape(str(new_label), {"'": "&apos;", '"': "&quot;"})
    updated_count = 0

    def replace_block(match):
        nonlocal updated_count
        block = match.group(0)
        if get_tag_value(block, "fullName") != target_name:
            return block
        updated_count += 1
        return re.sub(r"<label>[\s\S]*?</label>", f"<label>{escaped}</label>", block, count=1)

    updated = re.sub(r"<value>[\s\S]*?</value>", replace_block, xml_text)
    if updated_count != 1:
        raise RuntimeError(f"Could not uniquely update picklist value '{target_name}'.")
    return updated


def get_standard_value_set_label(xml_text, target_name):
    # Same idea as `get_picklist_label`, but for standard value sets.
    blocks = re.findall(r"<standardValue>[\s\S]*?</standardValue>", xml_text)
    matches = [block for block in blocks if get_tag_value(block, "fullName") == target_name]
    if len(matches) != 1:
        raise RuntimeError(f"Could not uniquely find picklist value '{target_name}' in metadata.")
    label = get_tag_value(matches[0], "label")
    return label or target_name


def update_standard_value_set_label(xml_text, target_name, new_label):
    # Updates a standard value set label, inserting `<label>` if Salesforce omitted it.
    escaped = escape(str(new_label), {"'": "&apos;", '"': "&quot;"})
    updated_count = 0

    def replace_block(match):
        nonlocal updated_count
        block = match.group(0)
        if get_tag_value(block, "fullName") != target_name:
            return block
        updated_count += 1
        if re.search(r"<label>[\s\S]*?</label>", block):
            return re.sub(r"<label>[\s\S]*?</label>", f"<label>{escaped}</label>", block, count=1)
        return block.replace("</standardValue>", f"    <label>{escaped}</label>\n</standardValue>")

    updated = re.sub(r"<standardValue>[\s\S]*?</standardValue>", replace_block, xml_text)
    if updated_count != 1:
        raise RuntimeError(f"Could not uniquely update picklist value '{target_name}'.")
    return updated


def parse_filter_target(target_name, line_number=None):
    # `listViewFilterValue` uses `targetName` in a compact syntax:
    #   FieldApiName
    #   FieldApiName|operation|occurrence
    # Example: `Region__c|contains|2`
    # This helper parses and validates that syntax into a structured dict.
    parts = [part.strip() for part in target_name.split("|")]
    parsed = {"field": "", "operation": "", "index": 1}
    line_prefix = f"CSV line {line_number}: " if line_number else ""

    if parts and parts[0]:
        parsed["field"] = parts[0]
    if len(parts) >= 2 and parts[1]:
        parsed["operation"] = parts[1]
    if len(parts) >= 3 and parts[2]:
        try:
            parsed["index"] = int(parts[2])
        except ValueError as exc:
            raise RuntimeError(
                f"{line_prefix}invalid targetName '{target_name}'. "
                "The optional third part must be an integer occurrence."
            ) from exc
    if len(parts) > 3:
        raise RuntimeError(
            f"{line_prefix}invalid targetName '{target_name}'. "
            "Expected 'FieldApiName' or 'FieldApiName|operation|occurrence'."
        )

    if not parsed["field"]:
        raise RuntimeError(
            f"{line_prefix}invalid targetName '{target_name}'. "
            "Expected 'FieldApiName' or 'FieldApiName|operation|occurrence'."
        )
    validate_list_view_field_name(parsed["field"], line_number or "unknown")
    if parsed["operation"] and parsed["operation"] not in SUPPORTED_FILTER_OPERATIONS:
        suggestion = suggest_value(parsed["operation"], SUPPORTED_FILTER_OPERATIONS)
        suggestion_message = f" Did you mean '{suggestion}'?" if suggestion else ""
        raise RuntimeError(
            f"{line_prefix}unsupported filter operation '{parsed['operation']}' in targetName '{target_name}'. "
            f"Supported values: {', '.join(sorted(SUPPORTED_FILTER_OPERATIONS))}.{suggestion_message}"
        )
    if parsed["index"] < 1:
        raise RuntimeError(f"{line_prefix}invalid targetName '{target_name}'. occurrence must be 1 or greater.")
    return parsed


def find_filter_block(xml_text, target_name):
    # Finds the matching `<filters>...</filters>` block inside a List View metadata file.
    # If several filters use the same field, `occurrence` lets the CSV pick which one.
    target = parse_filter_target(target_name)
    matches = []
    for match in re.finditer(r"<filters>[\s\S]*?</filters>", xml_text):
        block = match.group(0)
        field_value = get_tag_value(block, "field")
        operation_value = get_tag_value(block, "operation")

        if field_value != target["field"]:
            continue
        if target["operation"] and operation_value != target["operation"]:
            continue
        matches.append(match)

    index = target["index"] - 1
    if index >= len(matches):
        criteria = target["field"]
        if target["operation"]:
            criteria += f" with operation '{target['operation']}'"
        raise RuntimeError(
            f"Could not find filter #{target['index']} for {criteria}. "
            "Use targetName like 'FieldApiName|contains|1' when needed."
        )
    return matches[index].group(0)


def get_list_view_filter_value(xml_text, target_name):
    # Reads the current filter value from the matched List View filter block.
    block = find_filter_block(xml_text, target_name)
    return get_tag_value(block, "value")


def update_list_view_filter_value(xml_text, target_name, new_value):
    # Updates only the filter block selected by `find_filter_block`.
    block = find_filter_block(xml_text, target_name)
    updated_block = replace_tag(block, "value", new_value, "filters")
    return xml_text.replace(block, updated_block, 1)


def get_root_tag(setting_type):
    # Maps each settingType to the XML root element of the metadata file it belongs to.
    # `replace_tag` needs this to insert missing tags in the right place.
    if setting_type in {
        "fieldLabel",
        "helpText",
        "defaultValue",
        "description",
        "formula",
        "picklistLabel",
        "relatedListLabel",
    }:
        return "CustomField"
    if setting_type in {"listViewLabel", "listViewFilterValue"}:
        return "ListView"
    if setting_type == "webLinkUrl":
        return "WebLink"
    if setting_type == "validationRuleFormula":
        return "ValidationRule"
    raise RuntimeError(f"Unsupported settingType '{setting_type}'.")


def get_current_value(xml_text, row):
    # Reads the current value from the retrieved metadata file so `check` and `preview`
    # modes can show the before/after comparison.
    setting_type = row["settingType"]
    if setting_type == "fieldLabel":
        return get_tag_value(xml_text, "label")
    if setting_type == "helpText":
        return get_tag_value(xml_text, "inlineHelpText")
    if setting_type == "defaultValue":
        return get_tag_value(xml_text, "defaultValue")
    if setting_type == "description":
        return get_tag_value(xml_text, "description")
    if setting_type == "formula":
        return get_tag_value(xml_text, "formula")
    if setting_type == "picklistLabel":
        storage = resolve_picklist_storage(row)
        if storage["kind"] == "standardValueSet":
            return get_standard_value_set_label(xml_text, row["targetName"])
        return get_picklist_label(xml_text, row["targetName"])
    if setting_type == "relatedListLabel":
        return get_tag_value(xml_text, "relationshipLabel")
    if setting_type == "listViewLabel":
        return get_tag_value(xml_text, "label")
    if setting_type == "listViewFilterValue":
        return get_list_view_filter_value(xml_text, row["targetName"])
    if setting_type == "webLinkUrl":
        return get_tag_value(xml_text, "url")
    if setting_type == "validationRuleFormula":
        return get_tag_value(xml_text, "errorConditionFormula")
    raise RuntimeError(f"CSV line {row['_line']}: unsupported settingType '{setting_type}'.")


def apply_update(xml_text, row, resolved):
    # Applies one resolved CSV row to the XML text.
    # `resolved` already contains the final string after label placeholders were expanded.
    setting_type = row["settingType"]
    root_tag = get_root_tag(setting_type)

    if setting_type == "fieldLabel":
        return replace_tag(xml_text, "label", resolved, root_tag)
    if setting_type == "helpText":
        return replace_tag(xml_text, "inlineHelpText", resolved, root_tag)
    if setting_type == "defaultValue":
        return replace_tag(xml_text, "defaultValue", resolved, root_tag)
    if setting_type == "description":
        return replace_tag(xml_text, "description", resolved, root_tag)
    if setting_type == "formula":
        return replace_tag(xml_text, "formula", resolved, root_tag)
    if setting_type == "picklistLabel":
        storage = resolve_picklist_storage(row)
        if storage["kind"] == "standardValueSet":
            return update_standard_value_set_label(xml_text, row["targetName"], resolved)
        return update_picklist_label(xml_text, row["targetName"], resolved)
    if setting_type == "relatedListLabel":
        return replace_tag(xml_text, "relationshipLabel", resolved, root_tag)
    if setting_type == "listViewLabel":
        return replace_tag(xml_text, "label", resolved, root_tag)
    if setting_type == "listViewFilterValue":
        return update_list_view_filter_value(xml_text, row["targetName"], resolved)
    if setting_type == "webLinkUrl":
        return replace_tag(xml_text, "url", resolved, root_tag)
    if setting_type == "validationRuleFormula":
        return replace_tag(xml_text, "errorConditionFormula", resolved, root_tag)
    raise RuntimeError(f"CSV line {row['_line']}: unsupported settingType '{setting_type}'.")


def apply_updates(xml_text, rows, alias, cache):
    # Applies all updates for one metadata file sequentially.
    # The output of one change becomes the input to the next.
    updated = xml_text
    for row in rows:
        resolved = resolve_template(row["template"], alias, cache)
        updated = apply_update(updated, row, resolved)
    return updated


def write_preview_csv(preview_path, preview_rows):
    # Writes a spreadsheet-friendly report showing what would change.
    headers = [
        "objectApiName",
        "componentName",
        "settingType",
        "targetName",
        "currentValue",
        "resolvedNewValue",
        "status",
        "message",
    ]
    with open(preview_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for row in preview_rows:
            writer.writerow(row)


def print_check_row(row, resolved_new_value):
    # Human-friendly console output for `check` mode.
    label = row["settingType"]
    details = []
    if row["componentName"]:
        details.append(row["componentName"])
    if row["targetName"]:
        details.append(row["targetName"])
    if details:
        label += f" ({' | '.join(details)})"
    print(f"- {label}: {resolved_new_value}")


def add_preview_row(preview_rows, row, current_value, resolved_new_value, status, message=""):
    # Keeps preview row construction centralized so the schema stays consistent.
    preview_rows.append(
        {
            "objectApiName": row["objectApiName"],
            "componentName": row["componentName"],
            "settingType": row["settingType"],
            "targetName": row["targetName"],
            "currentValue": current_value,
            "resolvedNewValue": resolved_new_value,
            "status": status,
            "message": message,
        }
    )


def main():
    # High-level execution flow:
    # 1. Parse CLI arguments.
    # 2. Read and validate the CSV.
    # 3. Retrieve the relevant metadata from Salesforce.
    # 4. Depending on the mode:
    #    - check: only print resolved target values
    #    - preview: compare current vs new values and write a report
    #    - prepare: write updated metadata into a work directory
    #    - deploy: prepare, copy into the project, and deploy to Salesforce
    parser = argparse.ArgumentParser(
        description=(
            "Apply custom-label-driven metadata updates for Salesforce object metadata.\n"
            "Supported settingType values: "
            + ", ".join(sorted(SUPPORTED_SETTING_TYPES))
            + "\n\n"
            "CSV format:\n"
            f"- {', '.join(CSV_HEADERS)}\n\n"
            "Examples:\n"
            "- Field description: Lead,My_Field__c,description,,{{My_Label}}\n"
            "- Formula field: Lead,My_Formula__c,formula,,TEXT(Status__c) = '{{My_Label}}'\n"
            "- Picklist label: Lead,Status__c,picklistLabel,Closed_Won,{{My_Label}}\n"
            "- Related list label: Lead,Account__c,relatedListLabel,,{{My_Label}}\n"
            "- List view label: Lead,MyView,listViewLabel,,{{My_Label}}\n"
            "- List view filter value: Lead,MyView,listViewFilterValue,B2B_Region_liste__c|contains|1,{{My_Label}}\n"
            "- Web link URL: Lead,MyButton,webLinkUrl,,/apex/Page?id={{My_Label}}\n"
            "- Validation rule formula: Lead,MyRule,validationRuleFormula,,AND(TEXT(Status__c) = '{{My_Label}}', TRUE)"
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    prepared_files = []

    parser.add_argument("--csv", required=True)
    parser.add_argument("--alias", required=True)
    parser.add_argument("--mode", choices=["check", "preview", "prepare", "deploy"], default="check")
    parser.add_argument("--work-dir", default=DEFAULT_WORK_DIR)
    parser.add_argument("--sf-timeout-seconds", type=int, default=DEFAULT_SF_TIMEOUT_SECONDS)
    args = parser.parse_args()

    project_root = Path.cwd()
    csv_path = Path(args.csv).resolve()
    work_dir = Path(args.work_dir).resolve()

    if not csv_path.exists():
        fail(f"CSV file not found: {csv_path}")

    rows = read_csv(csv_path)
    if not rows:
        fail("The CSV file contains no change rows.")
    if args.sf_timeout_seconds < 1:
        fail("--sf-timeout-seconds must be 1 or greater.")

    grouped = group_by_component(rows)
    label_cache = prefetch_label_values(args.alias, rows, args.sf_timeout_seconds)
    preview_rows = []

    if args.mode in ("prepare", "deploy"):
        # Rebuild the work directory from scratch so it contains only files from this run.
        if work_dir.exists():
            shutil.rmtree(work_dir)
        work_dir.mkdir(parents=True, exist_ok=True)

    print(f"Retrieving {len(grouped)} metadata component(s) in one batch...")
    retrieve_metadata_batch(args.alias, rows, args.sf_timeout_seconds)

    for group_key, component_rows in grouped.items():
        # Each group corresponds to one metadata file on disk.
        print(f"\nProcessing {group_key}")

        try:
            component_file = get_file_path(project_root, group_key)
            xml_text = component_file.read_text(encoding="utf-8")

            if args.mode in ("check", "preview"):
                # Non-destructive modes: read current values and compute the future ones,
                # but do not write any files.
                for row in component_rows:
                    current_value = get_current_value(xml_text, row)
                    resolved_new_value = resolve_template(row["template"], args.alias, label_cache)
                    status = "NO_CHANGE" if current_value == resolved_new_value else "WILL_CHANGE"

                    if args.mode == "check":
                        print_check_row(row, resolved_new_value)

                    add_preview_row(preview_rows, row, current_value, resolved_new_value, status)
                continue

            updated_xml = apply_updates(xml_text, component_rows, args.alias, label_cache)
            output_file = work_dir / Path(group_key)
            output_file.parent.mkdir(parents=True, exist_ok=True)
            output_file.write_text(updated_xml, encoding="utf-8")
            prepared_files.append((output_file, project_root / Path(group_key)))

            print(f"- prepared {output_file}")
        except Exception as exc:
            if args.mode in ("check", "preview"):
                # In preview-oriented modes we keep going and record the error per row so
                # the user gets a full report instead of failing on the first problem.
                for row in component_rows:
                    add_preview_row(preview_rows, row, "", "", "ERROR", str(exc))
                continue
            raise

    if args.mode == "preview":
        preview_path = project_root / "carve_out-preview.csv"
        write_preview_csv(preview_path, preview_rows)
        print(f"\nPreview report written to {preview_path}")
        return

    if args.mode == "prepare":
        print(f"\nPrepared metadata written to {work_dir}")
        return

    if args.mode == "deploy":
        # `deploy` mode intentionally copies prepared files back into the project before
        # running `sf project deploy start`, because the CLI deploy command expects files
        # from the Salesforce project structure.
        print("\nCopying prepared files into the project...")
        for prepared_file, project_file in prepared_files:
            project_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(prepared_file, project_file)
            print(f"- copied {prepared_file} -> {project_file}")

        print(f"\nDeploying {len(prepared_files)} prepared file(s) in one batch...")
        deploy_files(args.alias, [project_file for _, project_file in prepared_files], args.sf_timeout_seconds)

        print("\nDeployment finished.")


# if __name__ == "__main__":
#     main()

if __name__ == "__main__":
    # Mock data to simulate what read_csv would return
    test_rows = [
        {"objectApiName": "Lead", "componentName": "Status", "settingType": "picklistLabel", "targetName": "Open"},
        {"objectApiName": "Lead", "componentName": "MyField__c", "settingType": "fieldLabel", "template": "My Label"},
        {"objectApiName": "Account", "componentName": "Industry", "settingType": "picklistLabel", "targetName": "Banking"},
    ]
    
    # Example call (Change 'my-org-alias' to your actual alias)
    # Note: This will actually attempt to call 'sf', so ensure you are logged in 
    # or comment out 'run_sf' in the code to just see the prints.
    try:
        retrieve_metadata_batch("my-org-alias", test_rows, 30)
    except Exception as e:
        print(f"\nStopped at run_sf execution: {e}")

