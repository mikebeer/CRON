/* test_cron.rexx - run:  PATH=.:$PATH regina ./test_cron.rexx */
fails = 0; total = 0

call chk 'valid */5',            cron('VALID','*/5 * * * *'),        1
call chk 'valid names',          cron('VALID','0 9 * JAN-MAR MON-FRI'), 1
call chk 'invalid minute 60',    cron('VALID','60 * * * *'),         0
call chk 'invalid 4 fields',     cron('VALID','* * * *'),            0
call chk 'invalid step 0',       cron('VALID','*/0 * * * *'),        0
call chk 'invalid reversed',     cron('VALID','30-10 * * * *'),      0
call chk 'invalid name',         cron('VALID','0 0 * FOO *'),        0
call chk 'valid @daily',         cron('VALID','@daily'),             1

call chk 'next */15',            cron('NEXT','*/15 * * * *','2026-11-14 10:07'), '2026-11-14 10:15'
call chk 'next strictly after',  cron('NEXT','*/15 * * * *','2026-11-14 10:15'), '2026-11-14 10:30'
call chk 'next range/step',      cron('NEXT','5-30/10 * * * *','2026-11-14 10:06'), '2026-11-14 10:15'
call chk 'next hour rollover',   cron('NEXT','0 * * * *','2026-11-14 23:30'), '2026-11-15 00:00'
call chk 'next year rollover',   cron('NEXT','0 0 1 1 *','2026-12-31 23:59'), '2027-01-01 00:00'
call chk 'next weekdays',        cron('NEXT','30 2 * * 1-5','2026-11-14 12:00'), '2026-11-16 02:30'
call chk 'next sunday as 7',     cron('NEXT','0 0 * * 7','2026-11-14 12:00'), '2026-11-15 00:00'
call chk 'next sunday as SUN',   cron('NEXT','0 0 * * SUN','2026-11-14 12:00'), '2026-11-15 00:00'
call chk 'next feb 29',          cron('NEXT','0 0 29 2 *','2026-11-14 12:00'), '2028-02-29 00:00'
call chk 'next dom OR dow',      cron('NEXT','0 0 13 * 5','2026-11-14 12:00'), '2026-11-20 00:00'
call chk 'next dom OR dow (b)',  cron('NEXT','0 0 13 * 5','2026-11-20 12:00'), '2026-11-27 00:00'
call chk 'next month name',      cron('NEXT','0 8 15 MAR *','2026-11-14 12:00'), '2027-03-15 08:00'
call chk 'next @hourly',         cron('NEXT','@hourly','2026-11-14 10:07'), '2026-11-14 11:00'
call chk 'next @weekly',         cron('NEXT','@weekly','2026-11-14 10:07'), '2026-11-15 00:00'
call chk 'next list',            cron('NEXT','0,30 9,17 * * *','2026-11-14 09:30'), '2026-11-14 17:00'
call chk 'next iso T stamp',     cron('NEXT','0 12 * * *','2026-11-14T08:00:00'), '2026-11-14 12:00'
call chk 'next leap day rollover', cron('NEXT','0 0 * * *','2028-02-28 12:00'), '2028-02-29 00:00'
call chk 'next feb30 never',     cron('NEXT','0 0 30 2 *','2026-01-01 00:00'), ''

call chk 'match yes',            cron('MATCH','*/5 * * * *','2026-11-14 10:10'), 1
call chk 'match no',             cron('MATCH','*/5 * * * *','2026-11-14 10:11'), 0
call chk 'match dow Sat',        cron('MATCH','0 0 * * 6','2026-11-14 00:00'), 1
call chk 'match bad stamp',      left(cron('MATCH','* * * * *','2026-02-30 00:00'),6), 'ERROR:'

/* crontab / tick, Unix and simulated Windows, dry run */
ct = 'test.crontab'
call lineout ct, '# test'
call lineout ct, 'MAILTO=""'
call lineout ct, '*/10 * * * * echo every10'
call lineout ct, '0 12 * * 6 echo saturday_noon'
call lineout ct, '@hourly echo hourly'
call lineout ct, 'bogus line here'
call lineout ct, '0 0 1 1 * echo newyear'
call stream ct, 'C', 'CLOSE'

call value 'CRON_OS', 'UNIX', 'ENVIRONMENT'
call chk 'tick count 12:00 Sat', cron('TICK', ct, '2026-11-14 12:00', 'DRYRUN'), 3
call chk 'tick count 12:05',     cron('TICK', ct, '2026-11-14 12:05', 'DRYRUN'), 0
call chk 'tick missing file',    left(cron('TICK','nope.crontab','2026-11-14 12:00'),6), 'ERROR:'
say '--- unix job lines:'; call cron 'TICK', ct, '2026-11-14 12:00', 'DRYRUN'
call value 'CRON_OS', 'WIN32', 'ENVIRONMENT'
call chk 'os win',               cron('OS'), 'WIN'
say '--- windows job lines (simulated):'; call cron 'TICK', ct, '2026-11-14 12:00', 'DRYRUN'

/* real execution on this OS (sync so we can see output) */
call value 'CRON_OS', '', 'ENVIRONMENT'
say '--- real run, SYNC:'
call chk 'real tick',            cron('TICK', ct, '2026-11-14 12:00', 'SYNC VERBOSE'), 3

/* ADD / LIST / REMOVE */
call value 'CRON_OS', '', 'ENVIRONMENT'
ed = 'edit.crontab'
address system 'rm -f' ed
call chk 'list missing file',    left(cron('LIST',ed),6), 'ERROR:'
call chk 'add creates file',     cron('ADD', ed, '*/5   * * * *', 'echo five'), 'OK: added job 1'
call chk 'add 2nd',              cron('ADD', ed, '@daily', 'echo daily'), 'OK: added job 2'
call chk 'add bad expr',         left(cron('ADD', ed, '99 * * * *', 'x'),6), 'ERROR:'
call chk 'add empty cmd',        left(cron('ADD', ed, '* * * * *', ''),6), 'ERROR:'
call chk 'list shows 2 jobs',    words(translate(cron('LIST',ed),' ',x2c('0A'))) > 0 & pos('echo daily', cron('LIST',ed)) > 0, 1
call chk 'remove bad number',    left(cron('REMOVE', ed, 9),6), 'ERROR:'
call chk 'remove job 1',         left(cron('REMOVE', ed, 1),17), 'OK: removed job 1'
call chk 'list after remove',    pos('echo five', cron('LIST',ed)), 0
call chk 'renumbered',           left(cron('LIST',ed),3), '  1'
call chk 'remove last job',      left(cron('REMOVE', ed, 1),17), 'OK: removed job 1'
call chk 'list empty',           cron('LIST',ed), '(no jobs)'
/* comments / env lines and missing trailing newline survive */
address system 'printf "# keep me\nMAILTO=x\n0 1 * * * echo a" > ' ed
call chk 'add after no-newline', cron('ADD', ed, '0 2 * * *', 'echo b'), 'OK: added job 2'
call chk 'remove job 1 (keeps comments)', left(cron('REMOVE', ed, 1),17), 'OK: removed job 1'
address system 'grep -c "keep me\|MAILTO" ' ed ' > edit.cnt'
call chk 'comment+env kept',     strip(linein('edit.cnt')), 2
call stream 'edit.cnt', 'C', 'CLOSE'
address system 'rm -f' ed 'edit.cnt'

call stream ct, 'C', 'CLOSE'
address system 'rm -f' ct
say
say total 'tests,' fails 'failed'
exit (fails > 0)

chk: procedure expose fails total
  parse arg name, got, want
  total = total + 1
  if got == want then say 'ok   ' name
  else do
    fails = fails + 1
    say 'FAIL ' name ': got "'got'" want "'want'"'
  end
  return
