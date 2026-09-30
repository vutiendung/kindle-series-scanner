# Series Grouping & Badge Mode Documentation

This document explains how Amazon Kindle firmware handles **Series Grouping** and **Program Badges** (such as *Kindle Unlimited* and *Prime Reading*) within `/var/local/cc.db`, as well as how our scanner enforces clean grouping without unwanted badges.

---

## 1. Overview: Series Grouping vs. Program Badges

In Kindle firmware (5.13.4+), series grouping and badge display are controlled by separate mechanisms in the SQLite database (`cc.db`):

* **Series Grouping**: Controlled by the `Series` table, the `Entry:Item:Series` virtual collection row in `Entries`, and `p_seriesState = 0` on member books.
* **Badges (Kindle Unlimited / Prime Reading)**: Controlled purely by the `p_originType` and `p_contentState` columns on individual book entries in the `Entries` table.

> [!NOTE]
> Disabling badges (setting Badge Mode to **None**) **does not affect series grouping**. Your books will still stack together in reading order on the Kindle home screen and library.

---

## 2. Database Field Reference

### Program Badge Modes (`Entries` table)

| Mode | `p_originType` | `p_contentState` | Result on Device |
| :--- | :---: | :---: | :--- |
| **None** *(Default & Recommended)* | `0` | `1` | Clean cover thumbnail. **No Kindle Unlimited or Prime badges**. |
| **Kindle Unlimited (KU)** | `21` | `1` | Displays the **Kindle Unlimited** badge banner over the cover. |
| **KU + Prime Reading** | `NULL` | `0` | Displays the **Prime Reading / KU** badge banner. |

### Series Grouping Fields

* **`p_seriesState`** (`Entries` table):
  * `0`: Book is part of a series; hidden from standalone library view and grouped inside its series container.
  * `1`: Standalone book; visible in library view outside any series container.
* **`Series` Table**:
  * `d_seriesId`: `urn:collection:1:asin-<SERIES_KEY>`
  * `d_itemCdeKey`: Book's ASIN or UUID (`p_cdeKey`)
  * `d_itemPosition`: 0-indexed float position (e.g. `0.0`, `1.0`, `2.0`)
  * `d_itemPositionLabel`: Display label on Kindle (e.g. `"1"`, `"2"`, `"3"`)
  * `d_itemType`: `'Entry:Item'`
  * `d_seriesOrderType`: `'ordered'`

---

## 3. Implementation in `kindle-series-scanner`

In `src/db/sqlite_helper.lua`, the SQL generator explicitly enforces clean attributes:

```lua
-- When assigning books to a series:
UPDATE Entries
SET p_seriesState = 0,
    p_originType = 0,
    p_contentState = 1
WHERE p_cdeKey = '<book_cde_key>' AND p_type = 'Entry:Item';
```

When cleaning or resetting series:

```lua
-- When resetting books to standalone:
UPDATE Entries
SET p_seriesState = 1,
    p_originType = 0,
    p_contentState = 1
WHERE p_type = 'Entry:Item';
```

---

## 4. Manual Fix / CLI Troubleshooting

If books on your Kindle were previously assigned a Kindle Unlimited badge and you want to strip it:

```bash
# Connect to Kindle via SSH / USB terminal
mntroot rw
stop com.lab126.ccat 2>/dev/null

# Reset all book badges to 0 (None)
sqlite3 /var/local/cc.db "UPDATE Entries SET p_originType = 0, p_contentState = 1 WHERE p_type = 'Entry:Item' AND (p_originType = 21 OR p_originType IS NULL);"

start com.lab126.ccat 2>/dev/null
```
