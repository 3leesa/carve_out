# Carve-Out Update Script Guide

## Purpose

`carve_out-update.py` is a helper script that updates Salesforce metadata files using values stored in Salesforce Custom Labels.

Instead of editing metadata files one by one, the script reads a CSV mapping file and, for each row:

- identifies the Salesforce component to update
- reads the target Custom Label value from the org
- inserts that value into the correct metadata file
- optionally prepares the files for review or deploys them to the org

This is mainly useful for carve-out work where hardcoded text must be replaced consistently across many metadata components.

## Resources Used To Build The Script

The script was created from these sources of information available in this workspace and workflow:

1. Existing script behavior
   - The original `carve_out-update.py` already handled field metadata updates and Custom Label resolution.

2. Metadata files present in this Salesforce project
   - Field metadata under `force-app/main/default/objects/<Object>/fields/*.field-meta.xml`
   - List views under `force-app/main/default/objects/<Object>/listViews/*.listView-meta.xml`
   - Web links under `force-app/main/default/objects/<Object>/webLinks/*.webLink-meta.xml`
   - Validation rules under `force-app/main/default/objects/<Object>/validationRules/*.validationRule-meta.xml`

3. Real examples from the repository
   - [Leads_T8_Site_EHS_B2B.listView-meta.xml](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/objects/Lead/listViews/Leads_T8_Site_EHS_B2B.listView-meta.xml)
   - [Lead.object-meta.xml](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/objects/Lead/Lead.object-meta.xml)
   - [Modifier.webLink-meta.xml](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/objects/Lead/webLinks/Modifier.webLink-meta.xml)
   - [VR001_Lead_Appel_technique.validationRule-meta.xml](/C:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/objects/Lead/validationRules/VR001_Lead_Appel_technique.validationRule-meta.xml)

4. Salesforce CLI commands already used by the script
   - `sf project retrieve start`
   - `sf project deploy start`
   - `sf data query --use-tooling-api`

5. Your functional requirements from this conversation
   - support more metadata types
   - accept a simpler CSV
   - validate CSV typos early
   - work with both `,` and `;` separators

## Data The Script Needs

For the script to work, all of the following are required.

### 1. A Salesforce project structure

The script expects standard Salesforce DX source format inside:

```text
force-app/main/default/objects/
```

### 2. A valid CSV mapping file

The CSV header must be exactly:

```csv
objectApiName,componentName,settingType,targetName,template
```

The file may use either:

- comma `,` separators
- semicolon `;` separators

### 3. A Salesforce org alias

The script needs an org alias passed with `--alias`.

Example:

```powershell
--alias dev4
```

This alias is used to:

- retrieve metadata from the org
- query Custom Label values
- deploy the changed files

### 4. Custom Labels existing in Salesforce

The `template` column can contain placeholders like:

```text
{{My_Custom_Label}}
```

The script queries Salesforce for those label values through Tooling API on `ExternalString`.

### 5. Correct metadata references in the CSV

Each row must identify:

- the object
- the component inside that object
- the kind of metadata value to update

## CSV Column Definitions

### `objectApiName`

The Salesforce object API name.

Examples:

- `Lead`
- `Account`
- `AcceptanceReport__c`

### `componentName`

The API name of the component being updated.

Examples:

- field: `Status__c`
- list view: `Leads_T8_Site_EHS_B2B`
- web link: `Modifier`
- validation rule: `VR001_Lead_Appel_technique`

### `settingType`

Defines what kind of metadata value the row updates.

Supported values:

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

### `targetName`

Used only for setting types that need a more specific target.

Rules:

- leave blank for most setting types
- required for `picklistLabel`
- required for `listViewFilterValue`

Examples:

- for `picklistLabel`
  - `Closed_Won`

- for `listViewFilterValue`
  - `B2B_Region_liste__c|contains|1`

Meaning of the list view filter format:

- first part: field API name
- second part: filter operation
- third part: occurrence number if there are multiple matching filters

### `template`

The new value to write into metadata.

It can contain:

- plain text
- formulas
- URLs
- one or more Custom Label placeholders like `{{My_Label}}`

Examples:

- `{{LBL_FIELD_HELP}}`
- `/apex/MyPage?id={{LBL_PAGE_ID}}`
- `AND(ISPICKVAL(Status, "{{LBL_STATUS}}"), TRUE)`

## What Metadata Can Be Updated

### Field metadata

The script supports:

- Default Value
- Description
- Field Label
- Formula
- Help Text
- Picklist Label
- Related List Label

Source path pattern:

```text
force-app/main/default/objects/<Object>/fields/<Component>.field-meta.xml
```

### List views

The script supports:

- Label
- Filter value

Source path pattern:

```text
force-app/main/default/objects/<Object>/listViews/<Component>.listView-meta.xml
```

### Web links

The script supports:

- Button or Link URL

Source path pattern:

```text
force-app/main/default/objects/<Object>/webLinks/<Component>.webLink-meta.xml
```

### Validation rules

The script supports:

- Error Condition Formula

Source path pattern:

```text
force-app/main/default/objects/<Object>/validationRules/<Component>.validationRule-meta.xml
```

## Execution Order Of The Methods

Below is the method execution flow when the script is run normally.

### 1. `main()`

This is the entry point.

It:

- reads command line arguments
- checks the CSV exists
- calls `read_csv()`
- groups rows by metadata file with `group_by_component()`
- loops through each component group
- decides what to do depending on mode: `check`, `preview`, `prepare`, or `deploy`

### 2. `read_csv(csv_path)`

This reads and validates the CSV file.

It:

- detects whether the separator is `,` or `;`
- reads the CSV header
- checks the header is correct
- normalizes each row using `normalize_row()`
- validates each row using `validate_row()`

### 3. `normalize_row(row, line_number)`

This trims values and adds the original CSV line number for clearer error messages.

### 4. `validate_row(row)`

This checks that the row is valid before any metadata work starts.

During validation it also uses:

- `validate_template()`
- `validate_api_name()`
- `suggest_value()`
- `parse_filter_target()` for list view filters

### 5. `group_by_component(rows)`

This groups CSV rows by the physical metadata file they belong to.

It uses:

- `resolve_group_key(row)`

### 6. `resolve_group_key(row)`

This converts the row into the metadata file path.

It uses:

- `build_default_relative_path(objectApiName, componentName, settingType)`

### 7. `build_default_relative_path(...)`

This determines which file path pattern to use based on `settingType`.

For example:

- field updates go to `fields/*.field-meta.xml`
- list view updates go to `listViews/*.listView-meta.xml`
- web link updates go to `webLinks/*.webLink-meta.xml`
- validation rule updates go to `validationRules/*.validationRule-meta.xml`

### 8. Per component group: `retrieve_metadata(alias, row)`

For each grouped file, the script retrieves the matching metadata from Salesforce using `sf project retrieve start`.

It uses:

- `run_sf(args)`

### 9. `get_file_path(project_root, group_key)`

After retrieve, this confirms the file exists locally and returns its path.

### 10. Read local XML

`main()` reads the retrieved metadata file into memory.

### 11. Mode-specific behavior

#### If mode is `check` or `preview`

For each row:

- `get_current_value(xml_text, row)` reads the current metadata value
- `resolve_template(template, alias, cache)` resolves any Custom Labels
- status is calculated as `NO_CHANGE` or `WILL_CHANGE`

If `check`:

- `print_check_row(row, resolved_new_value)` prints the intended value

If `preview`:

- `add_preview_row(...)` stores a result line for the output CSV
- at the end `write_preview_csv(...)` writes `carve_out-preview.csv`

#### If mode is `prepare` or `deploy`

For each grouped component:

- `apply_updates(xml_text, rows, alias, cache)` updates the XML in memory
- the resulting file is written into `.carve_out_work`

If `deploy`:

- each prepared file is copied into the project source folder
- `deploy_file(alias, file_path)` deploys it
- `deploy_file()` uses `run_sf(args)`

## Internal Value Resolution Methods

These methods are used while reading or modifying metadata.

### `resolve_template(template, alias, cache)`

Replaces `{{Label_Name}}` placeholders with actual label values.

It uses:

- `get_label_value(alias, label_name)`

### `get_label_value(alias, label_name)`

Queries Salesforce Tooling API for the Custom Label value.

It uses:

- `run_sf(args)`

### `get_current_value(xml_text, row)`

Reads the current value from the XML depending on `settingType`.

It uses helper methods such as:

- `get_tag_value()`
- `get_picklist_label()`
- `get_list_view_filter_value()`

### `apply_updates(xml_text, rows, alias, cache)`

Loops through all rows for one metadata file and applies them one by one.

It uses:

- `resolve_template()`
- `apply_update()`

### `apply_update(xml_text, row, resolved)`

Chooses the correct update method depending on `settingType`.

It uses helper methods such as:

- `replace_tag()`
- `update_picklist_label()`
- `update_list_view_filter_value()`
- `get_root_tag()`

## List View Filter Helper Methods

These methods are specific to `listViewFilterValue`.

### `parse_filter_target(target_name, line_number=None)`

Parses values like:

```text
B2B_Region_liste__c|contains|1
```

### `find_filter_block(xml_text, target_name)`

Finds the correct `<filters>` block in the list view XML.

### `get_list_view_filter_value(xml_text, target_name)`

Reads the current value from that filter block.

### `update_list_view_filter_value(xml_text, target_name, new_value)`

Updates the value inside that filter block.

## Generic XML Helper Methods

### `get_tag_value(xml_text, tag_name)`

Reads the value of a simple XML tag.

### `replace_tag(xml_text, tag_name, new_value, root_tag)`

Replaces a simple XML tag value, escaping XML characters when needed.

### `get_picklist_label(xml_text, target_name)`

Finds the correct picklist value block and reads its label.

### `update_picklist_label(xml_text, target_name, new_label)`

Updates the label inside the correct picklist value block.

## Run Modes

### `check`

Shows what the resolved new values would be.

### `preview`

Creates `carve_out-preview.csv` showing:

- current value
- resolved new value
- status
- error message if any

### `prepare`

Creates the modified files in:

```text
.carve_out_work/
```

No deploy is done.

### `deploy`

Creates modified files, copies them into the project, and deploys them to the target org.

## Recommended Usage Order

For safest use:

1. `check`
2. `preview`
3. `prepare`
4. `deploy`

Examples:

```powershell
python carve_out-update.py --csv carve_out-mapping.csv --alias dev4 --mode check
python carve_out-update.py --csv carve_out-mapping.csv --alias dev4 --mode preview
python carve_out-update.py --csv carve_out-mapping.csv --alias dev4 --mode prepare
python carve_out-update.py --csv carve_out-mapping.csv --alias dev4 --mode deploy
```

## Important Functional Notes

- A successful deploy does not always mean metadata was effectively changed.
- If `resolvedNewValue` is the same as the current metadata value, Salesforce may treat the deploy as a no-op.
- In that case, the component Last Modified Date in the org may not change.
- The script validates many CSV typos early, but it cannot fully detect every business typo before retrieve or deploy.

