import json, pathlib, sys, time
import duckdb
config = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
out = pathlib.Path(config["output"])
source = pathlib.Path(config["input"])
scratch = out / "scratch"
scratch.mkdir()
started = time.perf_counter()
def ident(value):
    return '"' + value.replace('"', '""') + '"'
def literal(value):
    return "'" + str(value).replace("'", "''") + "'"
try:
    with duckdb.connect(config={"memory_limit": f'{config["memory_gb"]}GB',
                               "threads": str(config["threads"]),
                               "temp_directory": str(scratch),
                               "max_temp_directory_size": f'{config["max_temp_gb"]}GB',
                               "preserve_insertion_order": "false"}) as con:
        if source.suffix.lower() == ".parquet":
            relation = con.read_parquet(str(source))
        else:
            relation = con.read_csv(str(source), all_varchar=True, ignore_errors=False)
        relation.create_view("source_data")
        for col in (config["group"], config["value"]):
            if col and col not in relation.columns:
                raise ValueError(f"Column not found: {col}")
        if config["group"]:
            group = ident(config["group"])
            fields = f'{group} AS group_value, COUNT(*) AS row_count'
            if config["value"]:
                value = ident(config["value"])
                fields += f', SUM(TRY_CAST({value} AS DOUBLE)) AS numeric_sum'
                fields += f', COUNT(*) FILTER (WHERE {value} IS NOT NULL AND TRY_CAST({value} AS DOUBLE) IS NULL) AS invalid_numeric_count'
            sql = f'SELECT {fields} FROM source_data GROUP BY {group}'
        else:
            sql = 'SELECT COUNT(*) AS row_count FROM source_data'
        target = out / "result.parquet"
        con.execute(f'COPY ({sql}) TO {literal(target)} (FORMAT PARQUET, COMPRESSION ZSTD)')
        count = con.execute('SELECT COUNT(*) FROM read_parquet(?)', [str(target)]).fetchone()[0]
    report = {"status": "passed", "elapsed_seconds": round(time.perf_counter()-started, 3),
              "result_rows": count, "result": str(target), "config": config,
              "duckdb": duckdb.__version__, "sql": sql}
    (out / "analysis-result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True))
except Exception as exc:
    (out / "analysis-error.json").write_text(json.dumps({"status":"failed", "error":str(exc)}), encoding="utf-8")
    raise