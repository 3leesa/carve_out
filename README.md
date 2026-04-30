# Salesforce Utilities

## Carve-Out Metadata Update Script

This folder contains `carve_out-update.py`, a helper script used to update Salesforce metadata with the current values of Custom Labels stored in a target org.

It is useful for carve-out work where text visible in CRM metadata cannot reference `$Label` dynamically and must be written directly into metadata XML instead.

## What The Script Does

The script reads a CSV mapping file and, for each row:

- identifies the metadata component to update
- retrieves the current metadata from Salesforce
- resolves one or more Custom Labels from the target org
- injects the resolved value into the correct XML tag
- optionally prepares files for review or deploys them back to the org

## Why This Script Exists

Some metadata can use labels at runtime in code or UI layers, but many object-level metadata files cannot. For those cases, the current Custom Label value has to be copied into the metadata itself.

This script makes that process consistent and repeatable.

It was built from:

- the Salesforce DX project structure in this repository
- the XML shapes used by real metadata files under `force-app/main/default`
- Salesforce CLI commands for retrieve, query, and deploy
- the carve-out requirement to align metadata text with current CRM Custom Labels

## Supported Metadata

The script currently supports these `settingType` values:

- `defaultValue`
- `description`
- `fieldLabel`
- `formula`
- `helpText`
- `picklistLabel`
- `relatedListLabel`
- `listViewLabel`
- `listViewFilterValue`
- `webLinkUrl`
- `validationRuleFormula`

These settings map to standard Salesforce DX metadata locations such as:

- `force-app/main/default/objects/<Object>/fields/*.field-meta.xml`
- `force-app/main/default/objects/<Object>/listViews/*.listView-meta.xml`
- `force-app/main/default/objects/<Object>/webLinks/*.webLink-meta.xml`
- `force-app/main/default/objects/<Object>/validationRules/*.validationRule-meta.xml`
- `force-app/main/default/standardValueSets/*.standardValueSet-meta.xml`

## Important Standard Metadata Note

Not every visible label is stored in the same metadata file.

Example: `Lead.LeadSource` is a standard picklist. Its local field file only contains the field definition, while the picklist values themselves are stored in `standardValueSets`.

Because of that, the script includes explicit handling for standard value set storage when needed instead of assuming all picklist labels live in `objects/<Object>/fields`.

## Input CSV Format

The CSV header must be exactly:

```csv
objectApiName,componentName,settingType,targetName,template
```

Both separators are accepted:

- comma `,`
- semicolon `;`

### Column meaning

- `objectApiName`: object API name, for example `Lead` or `Account`
- `componentName`: field, list view, web link, or validation rule API name
- `settingType`: kind of metadata value to update
- `targetName`: extra target detail for settings that need one, such as a picklist value API name
- `template`: final value pattern to write, including optional `{{Custom_Label_Name}}` placeholders

### Example row

```csv
Lead,My_Field__c,description,,{{My_Label}}
```

## Custom Label Resolution

The script treats placeholders like `{{Brand_Name}}` as Salesforce Custom Label API names.

It retrieves their current values from the target org through Salesforce Tooling API on `ExternalString`, then substitutes those values into the metadata update.

This means the org passed with `--alias` is the source of truth for label content.

## Run Modes

- `check`: show the resolved target value for each row
- `preview`: create a CSV report with current value, new value, and status
- `prepare`: write updated metadata files into `.carve_out_work/`
- `deploy`: prepare files, copy them into the project, and deploy them

Recommended order:

1. `check`
2. `preview`
3. `prepare`
4. `deploy`

## Method Execution Order

Below is the practical order in which methods are executed during a normal run.

### Common startup flow

1. `main()`
   Parses arguments, validates the file paths, and decides the mode.

2. `read_csv(csv_path)`
   Opens the mapping file, detects the separator, validates the header, and builds row objects.

3. `normalize_row(row, line_number)`
   Runs once per CSV row while reading to trim values and add the source line number.

4. `validate_row(row)`
   Runs once per CSV row after reading.

5. During `validate_row()`, helper methods may run:
   - `validate_template(row)`
   - `validate_api_name(...)`
   - `parse_filter_target(...)`
   - `validate_list_view_field_name(...)`
   - `suggest_value(...)` when a typo hint is needed

6. `group_by_component(rows)`
   Groups rows by the metadata file they belong to.

7. `resolve_group_key(row)`
   Builds the grouping key for each row.

8. `build_default_relative_path(...)`
   Maps each row to the expected Salesforce DX metadata path.

9. `resolve_picklist_storage(row)`
   Runs when needed for `picklistLabel`, especially standard value set cases like `Lead.LeadSource`.

10. `prefetch_label_values(alias, rows, timeout_seconds)`
    Reads all `{{Custom_Label}}` placeholders and queries them in batches.

11. During `prefetch_label_values()`, helper methods may run:
    - `extract_label_names(rows)`
    - `chunked(items, size)`
    - `run_sf(...)`

12. `retrieve_metadata_batch(alias, rows, timeout_seconds)`
    Retrieves all required metadata components from Salesforce in one batch.

13. During `retrieve_metadata_batch()`, helper methods may run:
    - `get_metadata_member(row)`
    - `resolve_picklist_storage(row)` when required
    - `run_sf(...)`

14. For each grouped component, `get_file_path(project_root, group_key)`
    Confirms the retrieved metadata file exists locally.

15. `main()` reads the XML file from disk into memory.

### If mode is `check` or `preview`

16. `get_current_value(xml_text, row)`
    Reads the current metadata value from the XML.

17. During `get_current_value()`, helper methods may run:
    - `get_tag_value(...)`
    - `get_picklist_label(...)`
    - `get_standard_value_set_label(...)`
    - `get_list_view_filter_value(...)`
    - `find_filter_block(...)`
    - `parse_filter_target(...)`

18. `resolve_template(template, alias, cache)`
    Replaces placeholders like `{{Brand_Name}}` with the current Custom Label values from the org.

19. During `resolve_template()`, `get_label_value(...)` runs only if a label is missing from cache.

20. If mode is `check`, `print_check_row(row, resolved_new_value)`
    Prints the intended result for the row.

21. `add_preview_row(...)`
    Stores the current value, resolved value, and status.

22. If mode is `preview`, `write_preview_csv(...)`
    Writes the preview report to `carve_out-preview.csv`.

### If mode is `prepare` or `deploy`

16. `apply_updates(xml_text, rows, alias, cache)`
    Applies all updates for one metadata file in memory.

17. During `apply_updates()`, for each row:
    - `resolve_template(...)`
    - `apply_update(...)`

18. During `apply_update()`, helper methods may run depending on `settingType`:
    - `get_root_tag(...)`
    - `replace_tag(...)`
    - `update_picklist_label(...)`
    - `update_standard_value_set_label(...)`
    - `update_list_view_filter_value(...)`
    - `find_filter_block(...)`
    - `resolve_picklist_storage(...)`

19. The updated XML is written into `.carve_out_work/`.

20. If mode is `prepare`, the script stops after writing prepared files.

21. If mode is `deploy`, the prepared files are copied back into the project source tree.

22. `deploy_files(alias, file_paths, timeout_seconds)`
    Deploys the changed files to Salesforce.

23. During `deploy_files()`, `run_sf(...)`
    Executes `sf project deploy start`.

## Usage

Run from the repository root or adjust paths accordingly.

```powershell
python salesforce/carve_out-update.py --csv salesforce/carve_out-mapping.csv --alias dev4 --mode check
python salesforce/carve_out-update.py --csv salesforce/carve_out-mapping.csv --alias dev4 --mode preview
python salesforce/carve_out-update.py --csv salesforce/carve_out-mapping.csv --alias dev4 --mode prepare
python salesforce/carve_out-update.py --csv salesforce/carve_out-mapping.csv --alias dev4 --mode deploy
```

## Requirements

- Salesforce CLI available as `sf`
- a valid Salesforce org alias
- a Salesforce DX project structure under `force-app/main/default`
- Custom Labels already present in the target org

## Validation Behavior

The script validates a lot before changing anything:

- exact CSV header
- accepted separator format
- supported `settingType`
- API-name style fields
- `targetName` rules for picklists and list view filters
- malformed `{{Label_Name}}` placeholders

This helps catch mapping mistakes early, before retrieve or deploy.

## Files In This Folder

- [carve_out-update.py](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/salesforce/carve_out-update.py): main script
- [carve_out-mapping.csv](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/salesforce/carve_out-mapping.csv): example mapping input
- [carve_out-update-guide.md](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/salesforce/carve_out-update-guide.md): detailed functional guide
- [python-for-carve-out-update.md](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/salesforce/python-for-carve-out-update.md): Python concepts used by the script, explained in plain language

## Good To Know

- A successful deploy can still be a no-op if the new value is the same as the current metadata value.
- The script is designed around supported metadata patterns, not every possible Salesforce metadata type.
- If another standard picklist behaves like `LeadSource`, the script may need an extra mapping for that storage pattern.
