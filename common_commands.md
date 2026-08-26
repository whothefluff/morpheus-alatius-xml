Reorder compound verbs file

```bash
sort stemlib/Latin/stemsrc/vbs.cmp.ml -o stemlib/Latin/stemsrc/vbs.cmp.ml
```

Run tests and save result in file

```bash
 make test 2>&1 | tee tests.log
```

Run for single word (local build)

```bash
echo "[WORD]" | MORPHLIB=stemlib bin/cruncher -L
```

Run for single word (docker image)
```bash
docker run --rm [IMAGE] /bin/sh -c 'echo "[WORD]" | MORPHLIB=stemlib bin/cruncher -L'
```