Postgres to Latex utilities
===========================

This repository contains a few utilities that let you go from PostgreSQL queries to latex files, which you can include in your source tree.

The code is a bit under-documented at the moment, but might still be helpful.

The main utility is ```executeQueries.pl```, which by default executes the queries contained in the file ```queries.yaml```.  The ```examples``` folder contains real-world examples of queries that were used.

There are several types of queries that are understood. The easiest of them (without a type specification) just expects the query to return a count. There is also the _switch_ type, which returns a struct-like latex template; the _table_ type outputs a latex table.

Running ```executeQueries.pl``` will create a file called results-new.yaml. After you created this file, rename it to ```results.yaml```, and feed it to ```generateTex.pl```, which will create an output tex file.

If you run ```executeQueries.pl``` several times, only new queries will be run - queries that already have results in ```results.yaml``` will be skipped.

A standard workflow, assuming the existence of queries.yaml is something along these lines:

```
./executeQueries.pl
# check the results in results-new.yaml against old results in results.yaml.
mv results-new.yaml results.yaml
./generateTex.pl > output.tex
```