# Python Notes For `carve_out-update.py`

## Purpose Of This Document

This document explains the Python language concepts used in `carve_out-update.py` so that someone who is not very familiar with Python can still understand what the script is doing.

It is not a full Python course. It is a focused reading guide for this script.

## How To Read A Python Script

Python executes code from top to bottom.

In this script:

- imports are loaded first
- constants are defined next
- functions are defined after that
- nothing actually runs until the last block calls `main()`

The final block is:

```python
if __name__ == "__main__":
    main()
```

This means:

- if the file is executed directly, run `main()`
- if the file is imported by another Python file, do not run `main()` automatically

## Imports

At the top of the script you see:

```python
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
```

These are standard Python modules.

What they are used for in this script:

- `argparse`: read command-line arguments like `--csv`, `--alias`, `--mode`
- `csv`: read the mapping file and write the preview report
- `difflib`: suggest similar values when the CSV contains a typo
- `json`: parse JSON returned by Salesforce CLI
- `os`: detect whether the script runs on Windows
- `re`: search and replace text with regular expressions
- `shutil`: delete folders and copy files
- `subprocess`: run `sf` CLI commands from Python
- `sys`: exit the script or write errors to stderr
- `Path`: build file paths in a safer and cleaner way
- `escape` and `unescape`: safely write XML values and read XML values

## Constants

Python variables written in uppercase are usually treated as constants by convention.

Example:

```python
DEFAULT_WORK_DIR = ".carve_out_work"
```

This does not mean Python enforces immutability. It means developers are signaling: this value is meant to stay fixed unless there is a good reason to change it.

The important constants in this script are:

- `DEFAULT_WORK_DIR`
- `DEFAULT_SF_TIMEOUT_SECONDS`
- `MAX_SOQL_LABELS_PER_QUERY`
- `CSV_HEADERS`
- `SUPPORTED_SETTING_TYPES`
- `SUPPORTED_FILTER_OPERATIONS`
- `STANDARD_VALUE_SET_FIELDS`

## Functions

Python functions are defined with `def`.

Example:

```python
def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)
```

This means:

- the function is named `fail`
- it accepts one input called `message`
- the indented block is the function body

Functions help break a large script into small reusable steps.

## Indentation

In Python, indentation is part of the syntax.

That means spaces are not just visual formatting. They define structure.

Example:

```python
if not csv_path.exists():
    fail(f"CSV file not found: {csv_path}")
```

The second line only belongs to the `if` because it is indented.

## Variables And Assignment

Python uses `=` for assignment.

Example:

```python
project_root = Path.cwd()
```

This stores the current working directory in the variable `project_root`.

Variables in Python do not need an explicit type declaration. Python infers the type from the value.

## Strings

Strings are text values.

Examples from the script:

```python
"check"
"LeadSource"
"Custom Label not found or not unique"
```

Python supports:

- single-line strings
- formatted strings
- escaped characters

### F-strings

The script uses many f-strings:

```python
f"CSV line {row['_line']}: template is required."
```

The `f` before the string means Python will evaluate expressions inside `{}` and insert their values into the final text.

This is heavily used for:

- error messages
- CLI arguments
- file names
- XML replacements

## Lists

Lists are ordered collections.

Example:

```python
CSV_HEADERS = ["objectApiName", "componentName", "settingType", "targetName", "template"]
```

Lists in this script are used for:

- CSV headers
- command arguments for `sf`
- batches of label names
- rows collected for preview output

Common list operations in the script:

- create a list with `[]`
- append with `.append(...)`
- loop through values with `for`
- build a list with list comprehension

### List comprehension

Example:

```python
normalized = {key: (value or "").strip() for key, value in row.items()}
```

This is a compact way to build a new structure by looping over an existing one.

Another example:

```python
deploy_paths = [str(path) for path in file_paths]
```

This means:

- for each `path` in `file_paths`
- convert it to string
- collect the results into a new list

## Dictionaries

Dictionaries store key-value pairs.

Example:

```python
normalized["_line"] = line_number
```

Here:

- `"_line"` is the key
- `line_number` is the value

Rows from `csv.DictReader` are dictionaries, which is why the script uses syntax like:

```python
row["settingType"]
row["template"]
row["componentName"]
```

The script also uses dictionaries to return structured mini-objects, for example:

```python
return {"kind": "standardValueSet", "name": standard_value_set_name}
```

## Sets

Sets store unique values.

Example:

```python
metadata_members = sorted({get_metadata_member(row) for row in rows})
```

This is used so the same metadata member is not retrieved twice.

Another example is collecting label names only once before querying Salesforce.

## Tuples

Tuples are fixed ordered groups of values.

Example:

```python
("Lead", "LeadSource")
```

In this script, tuples are used as dictionary keys in `STANDARD_VALUE_SET_FIELDS`.

That allows the script to map:

- object API name
- component name

to a specific standard value set name.

## Conditionals

Python uses `if`, `elif`, and `else` for branching.

Example:

```python
if first_line.count(";") > first_line.count(","):
    delimiter = ";"
elif first_line.count(",") > first_line.count(";"):
    delimiter = ","
else:
    delimiter = ","
```

This is how the script decides which separator the CSV uses.

Conditionals are also used to:

- choose the metadata file path
- decide the behavior for each `settingType`
- switch behavior by mode: `check`, `preview`, `prepare`, `deploy`

## Loops

Python uses `for` loops to iterate through collections.

Example:

```python
for row in rows:
    validate_row(row)
```

That means:

- take each item in `rows`
- store it temporarily in `row`
- run the indented block

The script uses loops to:

- validate rows
- group rows by file
- retrieve label values in batches
- apply updates row by row
- build CLI argument lists

## `return`

Functions use `return` to send back a result.

Example:

```python
return result.stdout
```

This means the caller receives the text output of the CLI command.

Some functions return:

- strings
- lists
- dictionaries
- updated XML text

Some functions return nothing explicitly. In Python, that means they return `None`.

## Exceptions And Error Handling

Python uses exceptions to signal failures.

Example:

```python
raise RuntimeError(f"Custom Label not found or not unique: {label_name}")
```

This stops normal execution and moves control to the nearest matching `except` block, if one exists.

The script uses exceptions a lot because it is a validation-heavy automation tool.

### `try` / `except`

Example:

```python
try:
    result = subprocess.run(...)
except subprocess.TimeoutExpired as exc:
    raise RuntimeError(...) from exc
```

This means:

- try to run the CLI command
- if that specific timeout error happens, convert it into a clearer business error

Another important block is in `main()`:

```python
try:
    ...
except Exception as exc:
    ...
```

That block lets `check` and `preview` continue collecting errors per component instead of crashing immediately.

### `fail()` vs `raise RuntimeError(...)`

The script uses two styles:

- `fail(...)`: print to stderr and exit immediately
- `raise RuntimeError(...)`: raise a Python exception to be handled by calling code

Why both exist:

- `fail(...)` is used for top-level fatal setup problems
- `RuntimeError` is used inside helper functions so errors can propagate naturally

## `with open(...)`

Example:

```python
with open(csv_path, newline="", encoding="utf-8-sig") as f:
    ...
```

The `with` statement ensures the file is properly closed after use, even if an error occurs.

This is the preferred Python pattern for file handling.

The script uses it for:

- reading the CSV
- writing the preview CSV

## Enumerate

Example:

```python
rows = [normalize_row(row, i) for i, row in enumerate(reader, start=2)]
```

`enumerate(...)` adds a counter while looping.

Here it is used so each CSV row remembers its original line number, starting at 2 because line 1 is the header.

## `next(...)`

Example:

```python
first_line = next((line for line in sample.splitlines() if line.strip()), "")
```

This means:

- find the first non-empty line
- if none exists, use `""`

This is a compact Python pattern for “first matching item or default value”.

## Generators And `yield`

Example:

```python
def chunked(items, size):
    for index in range(0, len(items), size):
        yield items[index : index + size]
```

`yield` makes this a generator function.

Instead of building all batches at once, it produces one batch at a time when needed.

That is memory-efficient and fits the problem well.

In practical terms, `chunked(...)` splits label names into groups of up to 100 so the SOQL query stays manageable.

## Regular Expressions

The `re` module is heavily used.

Regular expressions are patterns used to search text.

Examples in the script:

```python
re.fullmatch(r"[A-Za-z0-9_]+(__c|__mdt|__e|__x)?", value)
re.findall(r"\{\{([A-Za-z0-9_]+)\}\}", row["template"])
re.sub(r"<label>[\s\S]*?</label>", f"<label>{escaped}</label>", block, count=1)
```

They are used to:

- validate Salesforce API names
- find `{{Custom_Label}}` tokens
- find XML blocks
- replace XML tag contents

You do not need to memorize every regex to understand the script. The important thing is knowing that regex is used here for pattern-based validation and text replacement.

## Path Handling With `pathlib.Path`

Example:

```python
Path("force-app") / "main" / "default"
```

In Python, `/` between `Path` objects means “join these path parts”.

This is cleaner and safer than manual string concatenation for file paths.

Other useful examples in the script:

```python
Path.cwd()
Path(args.csv).resolve()
output_file.parent.mkdir(parents=True, exist_ok=True)
```

These mean:

- current working directory
- absolute path for an argument
- create parent folders if they do not already exist

## Running External Commands With `subprocess`

The `run_sf(...)` function wraps:

```python
subprocess.run(...)
```

This is how Python launches the Salesforce CLI.

Important parameters used:

- `capture_output=True`: keep stdout and stderr in Python
- `text=True`: return strings instead of raw bytes
- `shell=False`: run the command directly, more safely
- `timeout=...`: stop waiting if the command takes too long

After the call, the script checks:

- `result.returncode`
- `result.stdout`
- `result.stderr`

So Python is acting like a controller around the CLI, not replacing Salesforce CLI logic itself.

## JSON Parsing

Salesforce CLI is called with `--json`, so the script can parse structured output.

Example:

```python
parsed = json.loads(output)
records = parsed.get("result", {}).get("records", [])
```

This means:

- convert JSON text into Python dictionaries and lists
- safely read nested values
- default to `{}` or `[]` if a key is missing

This is much more reliable than trying to parse human-readable CLI text.

## XML Escaping And Unescaping

Metadata values may contain characters that are special in XML, such as:

- `&`
- `<`
- `>`
- quotes

That is why the script uses:

- `escape(...)` before writing values into XML
- `unescape(...)` after reading values from XML

Without that, valid business text could break the metadata file format.

## Nested Functions

There are small functions defined inside other functions, for example:

```python
def resolve_template(template, alias, cache):
    def repl(match):
        ...
```

and

```python
def update_picklist_label(xml_text, target_name, new_label):
    def replace_block(match):
        ...
```

These inner functions are local helpers.

They are useful when:

- the logic is only needed in one place
- the helper should access outer variables like `cache`, `target_name`, or `updated_count`

## `nonlocal`

Example:

```python
nonlocal updated_count
```

This appears in inner helper functions used during XML replacement.

It means:

- use the variable from the outer function
- do not create a new local variable with the same name

Without `nonlocal`, changing `updated_count` inside the inner function would not affect the outer variable.

## Boolean Logic

The script uses standard boolean operators:

- `and`
- `or`
- `not`

Example:

```python
if setting_type in {"picklistLabel", "listViewFilterValue"} and not row["targetName"]:
```

This reads almost like English:

- if the setting type is one of those values
- and target name is empty
- then raise an error

## Membership Tests

Python uses `in` to check whether a value belongs to a collection.

Examples:

```python
if setting_type in {"listViewLabel", "listViewFilterValue"}:
if label_name not in cache:
```

This is used throughout the script for:

- supported value checks
- mode checks
- dictionary cache checks

## Sorting

The script uses `sorted(...)` to keep outputs stable and predictable.

Example:

```python
metadata_members = sorted({get_metadata_member(row) for row in rows})
```

This helps:

- make behavior deterministic
- reduce noisy ordering differences
- simplify debugging

## Slicing

Example:

```python
items[index : index + size]
```

This is Python slice syntax.

It means “take a sub-list from `index` up to but not including `index + size`”.

That is the core of how `chunked(...)` creates batches.

## Truthy And Falsy Values

Python treats some values as false in conditions:

- `""`
- `[]`
- `{}`
- `None`
- `0`

Example:

```python
if not rows:
    fail("The CSV file contains no change rows.")
```

This means:

- if the list is empty, stop the script

Another example:

```python
return unescape(match.group(1)) if match else ""
```

If no regex match exists, return an empty string.

## Practical Reading Map For This Script

If you want to understand the script progressively, read it in this order:

1. `main()`
2. `read_csv()`
3. `validate_row()`
4. `group_by_component()`
5. `prefetch_label_values()`
6. `retrieve_metadata_batch()`
7. `get_current_value()` and `apply_update()`
8. the XML helper functions
9. `run_sf()`

That order is usually easier than reading from line 1 to the end without context.

## Mental Model Of What Python Is Doing Here

At a high level, Python is doing five jobs in this script:

1. Reading input data from CSV.
2. Validating business rules before doing risky work.
3. Calling Salesforce CLI and parsing its JSON output.
4. Searching and rewriting XML text.
5. Coordinating the workflow depending on the selected mode.

So if you ever feel lost in the syntax, come back to this simpler mental model:

- Python reads
- Python validates
- Python asks Salesforce for data
- Python transforms text
- Python writes or deploys the result

## Final Advice

To understand this script well, you do not need to master all of Python.

The most important concepts for this file are:

- functions
- dictionaries and lists
- loops and conditionals
- exceptions
- regular expressions
- file paths
- subprocess calls
- JSON parsing
- string interpolation with f-strings

Once those feel comfortable, the script becomes much easier to follow.
