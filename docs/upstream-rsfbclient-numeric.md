# Upstream report draft — rsfbclient NUMERIC/DECIMAL precision loss

**Status: drafted 2026-08-06, not filed.** Text for an issue against
[fernandobatels/rsfbclient](https://github.com/fernandobatels/rsfbclient).
File the issue first and let the maintainer choose the API shape before
writing a PR — the fix touches a public type, so guessing wrong costs a
rewrite.

Plamenix carries the change locally in `plamenix-core/vendor/`; the
vendored copies are the stopgap, this is how they eventually go away.

---

## Issue text

**Title:** NUMERIC/DECIMAL columns lose precision — coerced to `f64` at describe time

Both backends ask the engine for a `double` whenever a column's scale is
non-zero, which is every `NUMERIC(p,s)` and `DECIMAL(p,s)`. Firebird
stores those as an exact scaled integer, so the exactness is discarded
inside the driver, before any caller can reach the value.

`rsfbclient-rust/src/xsqlda.rs`, in `XSqlVar::coerce`:

```rust
ibase::SQL_SHORT | ibase::SQL_LONG | ibase::SQL_INT64 => {
    self.data_length = mem::size_of::<i64>() as i16;

    if self.scale == 0 {
        self.sqltype = ibase::SQL_INT64 as i16 + 1;
    } else {
        // Is actually a decimal or numeric value, so coerce as double
        self.scale = 0;
        self.sqltype = ibase::SQL_DOUBLE as i16 + 1;
    }
}
```

`rsfbclient-native/src/row.rs`, in `ColumnBuffer::from_xsqlvar`, does the
same thing, so the behaviour is identical in both.

### Why it matters

`NUMERIC(18,4)` is the conventional money type in Firebird schemas. Its
scaled integer runs up to 18 digits, past the 2^53 an `f64` represents
exactly, so large values come back altered. `f64` also cannot hold most
decimal fractions exactly, which shows up as soon as a value is used in
arithmetic or re-serialised rather than merely printed.

There is no way to recover the value downstream: by the time a `Column`
exists, the engine has already done the conversion.

The pure-Rust backend loses the metadata too. `coerce()` mutates the
stored `XSqlVar`, so `wire.rs` later reads the rewritten `sqltype` and
zeroed `scale` and passes the coerced type as `Column::raw_type` — a
caller cannot even detect that a column was `NUMERIC`. The native
backend captures `sqltype` before mutating, so `raw_type` there is still
the declared type.

### Reproducing

```sql
CREATE TABLE money_test (id INTEGER, amount NUMERIC(18,4));
INSERT INTO money_test VALUES (1, 99999999999999.9999);
```

```rust
let rows: Vec<(i32, f64)> = conn.query("SELECT id, amount FROM money_test", ())?;
// amount comes back as 100000000000000.0
```

### Suggested shape

The conversion traits can absorb this, so existing callers need not
change. Sketch:

- `Column` gains `scale: i16`, defaulted to 0 by the existing
  `Column::new`, set by a new `Column::with_scale`.
- Both backends stop the coercion and keep the scaled integer plus its
  scale.
- `ColumnToVal<f64>` gains a scaled-integer arm applying `10^scale`, so
  `row.get::<f64>()` keeps returning what it returns today:

```rust
impl ColumnToVal<f64> for Column {
    fn to_val(self) -> Result<f64, FbError> {
        match self.value {
            Floating(f) => Ok(f),
            Integer(i) if self.scale != 0 => Ok(i as f64 * 10f64.powi(self.scale as i32)),
            Null => Err(err_column_null("f64")),
            col => err_type_conv(col, "f64"),
        }
    }
}
```

- `ColumnToVal<String>` becomes the lossless accessor.
- `ColumnToVal<i64>` must **reject** a scaled column rather than return
  the unscaled integer, which would read `1234` as the value of
  `0.1234`.

Adding a public field to `Column` breaks struct literals, so this wants
a `0.28.0`. Alternatives worth the maintainer's opinion: gate the
behaviour behind a connection-builder opt-in instead of changing the
default, or expose `rust_decimal::Decimal` behind a feature.

Happy to send a PR once you have a preference on the shape.

---

## What Plamenix does locally

The vendored copies take a narrower route, because Plamenix cannot
change `rsfbclient-core` without vendoring a third crate:

- Both backends keep the scaled integer and render the exact decimal as
  `SqlType::Text`, matching how the native backend already surfaces
  `INT128` and `DECFLOAT`.
- `raw_type` stays the declared integer type code, so `plamenix-db`
  distinguishes an exact decimal from a real `VARCHAR`: text arriving on
  a column the engine declared as `SQL_SHORT`/`SQL_LONG`/`SQL_INT64` can
  only be the rendering.
- That feeds `ColumnValue::Decimal(String)`.

This is a workaround shaped by not owning `SqlType`. The upstream fix
above is the better design and should replace it.

While patching, the native backend's existing `apply_scale` turned out
to have a sign bug: it divided by the scale factor, and integer
truncation toward zero erased the sign of every value between -1 and 0,
so `-5` at scale `-4` rendered `0.0005`. That helper is used by the
`SQL_ARRAY` decoding Plamenix already vendors, not by upstream code, so
it is not part of the report above.
